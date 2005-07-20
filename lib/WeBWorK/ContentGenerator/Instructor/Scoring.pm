################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2003 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork-modperl/lib/WeBWorK/ContentGenerator/Instructor/Scoring.pm,v 1.46 2005/07/14 13:15:26 glarose Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package WeBWorK::ContentGenerator::Instructor::Scoring;
use base qw(WeBWorK::ContentGenerator::Instructor);

=head1 NAME
 
WeBWorK::ContentGenerator::Instructor::Scoring - Generate scoring data files

=cut

use strict;
use warnings;
use CGI qw();
use WeBWorK::Utils qw(readFile);
use WeBWorK::DB::Utils qw(initializeUserProblem);
use WeBWorK::Timing;


our @userInfoColumnHeadings = ("STUDENT ID", "login ID", "LAST NAME", "FIRST NAME", "SECTION", "RECITATION");
our @userInfoFields = ("student_id", "user_id","last_name", "first_name", "section", "recitation");

sub initialize {
	my ($self)     = @_;
	my $r          = $self->r;
	my $urlpath    = $r->urlpath;
	my $ce         = $r->ce;
	my $db         = $r->db;
	my $authz      = $r->authz;
	my $scoringDir = $ce->{courseDirs}->{scoring};
	my $courseName = $urlpath->arg("courseID");
	my $user       = $r->param('user');
    
	# Check permission
	return unless $authz->hasPermissions($user, "access_instructor_tools");
	return unless $authz->hasPermissions($user, "score_sets");
	
	my @selected = $r->param('selectedSet');
	my $scoreSelected = $r->param('scoreSelected');
	my $scoringFileName = $r->param('scoringFileName') || "${courseName}_totals";
	$scoringFileName =~ s/\.csv\s*$//; $scoringFileName .='.csv';  # must end in .csv
	$self->{scoringFileName}=$scoringFileName;
	
	$self->{padFields}  = defined($r->param('padFields') ) ? 1 : 0; 
	
	if (defined $scoreSelected && @selected) {

		my @totals                 = ();
		my $recordSingleSetScores  = $r->param('recordSingleSetScores');
		
		# pre-fetch users
		$WeBWorK::timer->continue("pre-fetching users") if defined($WeBWorK::timer);
		my @Users = $db->getUsers($db->listUsers);
		my %Users;
		foreach my $User (@Users) {
			next unless $User;
			$Users{$User->user_id} = $User;
		}
		my @sortedUserIDs = sort { 
			lc($Users{$a}->last_name) cmp lc($Users{$b}->last_name) 
				||
			lc($Users{$a}->first_name) cmp lc($Users{$b}->first_name)
				||
			lc($Users{$a}->user_id) cmp lc($Users{$b}->user_id)
			}

			keys %Users;
		#my @userInfo = (\%Users, \@sortedUserIDs);
		$WeBWorK::timer->continue("done pre-fetching users") if defined($WeBWorK::timer);
		
		my $scoringType            = ($recordSingleSetScores) ?'everything':'totals';
		my (@everything, @normal,@full,@info,@totalsColumn);
		@info             = $self->scoreSet($selected[0], "info", undef, \%Users, \@sortedUserIDs) if defined($selected[0]);
		@totals           = @info;
		my $showIndex     = defined($r->param('includeIndex')) ? defined($r->param('includeIndex')) : 0; 
		
     
		foreach my $setID (@selected) {
		    next unless defined $setID;
			if ($scoringType eq 'everything') {
				@everything = $self->scoreSet($setID, "everything", $showIndex, \%Users, \@sortedUserIDs);
				@normal = $self->everything2normal(@everything);
				@full = $self->everything2full(@everything);
				@info = $self->everything2info(@everything);
				@totalsColumn = $self->everything2totals(@everything);
				$self->appendColumns(\@totals, \@totalsColumn);
				$self->writeCSV("$scoringDir/s${setID}scr.csv", @normal);
				$self->writeCSV("$scoringDir/s${setID}ful.csv", @full);				
			} else {
				@totalsColumn  = $self->scoreSet($setID, "totals", $showIndex, \%Users, \@sortedUserIDs);
				$self->appendColumns(\@totals, \@totalsColumn);
			}	
		}
		my @sum_scores  = $self->sumScores(\@totals, $showIndex, \%Users, \@sortedUserIDs);
		$self->appendColumns( \@totals,\@sum_scores);
		$self->writeCSV("$scoringDir/$scoringFileName", @totals);

	} elsif (defined $scoreSelected) {
		$self->addbadmessage("You must select one or more sets for scoring");
	} 
	
	# Obtaining list of sets:
	#$WeBWorK::timer->continue("Begin listing sets") if defined $WeBWorK::timer;
	my @setNames =  $db->listGlobalSets();
	#$WeBWorK::timer->continue("End listing sets") if defined $WeBWorK::timer;
	my @set_records = ();
	#$WeBWorK::timer->continue("Begin obtaining sets") if defined $WeBWorK::timer;
	@set_records = $db->getGlobalSets( @setNames); 
	#$WeBWorK::timer->continue("End obtaining sets: ".@set_records) if defined $WeBWorK::timer;
	
	
	# store data
	$self->{ra_sets}              =   \@setNames; # ra_sets IS NEVER USED AGAIN!!!!!
	$self->{ra_set_records}       =   \@set_records;
}


sub body {
	my ($self)      = @_;
	my $r           = $self->r;
	my $urlpath     = $r->urlpath;
	my $ce          = $r->ce;
	my $authz       = $r->authz;
	my $scoringDir  = $ce->{courseDirs}->{scoring};
	my $courseName  = $urlpath->arg("courseID");
	my $user        = $r->param('user');
	
	my $scoringPage       = $urlpath->newFromModule($urlpath->module, courseID => $courseName);
	my $scoringURL        = $self->systemLink($scoringPage, authen=>0);
	
	my $scoringDownloadPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::ScoringDownload", 
	                                      courseID => $courseName
	);
	
	my $scoringFileName = $self->{scoringFileName};
	
	# Check permissions
	return CGI::div({class=>"ResultsWithError"}, "You are not authorized to access the Instructor tools.")
		unless $authz->hasPermissions($user, "access_instructor_tools");
	
	return CGI::div({class=>"ResultsWithError"}, "You are not authorized to score sets.")
		unless $authz->hasPermissions($user, "score_sets");

	print join("",
			CGI::start_form(-method=>"POST", -action=>$scoringURL),"\n",
			$self->hidden_authen_fields,"\n",
			CGI::hidden({-name=>'scoreSelected', -value=>1}),
			CGI::start_table({border=>1,}),
				CGI::Tr(
					CGI::td($self->popup_set_form),
					CGI::td(
						CGI::checkbox({ -name=>'includeIndex',
										-value=>1,
										-label=>'Include Index',
										-checked=>0,
									   },
						),
						CGI::br(),
						CGI::checkbox({ -name=>'includeTotals',
										-value=>1,
										-label=>'Include Total score column',
										-checked=>1,
									   },
						),
						CGI::br(),
						CGI::checkbox({ -name=>'includePercent',
										-value=>1,
										-label=>'Include Percent correct column',
										-checked=>1,
									   },
						),
						CGI::br(),
						CGI::checkbox({ -name=>'recordSingleSetScores',
										-value=>1,
										-label=>'Record Scores for Single Sets',
										-checked=>0,
									  },
									 'Record Scores for Single Sets'
						),
						CGI::br(),
						CGI::checkbox({ -name=>'padFields',
										-value=>1,
										-label=>'Pad Fields',
										-checked=>1,
									  },
									 'Pad Fields'
						),
					),
				),
				CGI::Tr(CGI::td({colspan =>2,align=>'center'},
					CGI::input({type=>'submit',value=>'Score selected set(s) and save to: ',name=>'score-sets'}),
					CGI::input({type=>'text', name=>'scoringFileName', size=>'40',value=>"$scoringFileName"})
				)),
			
		   CGI::end_table(),
	);

	
	if ($authz->hasPermissions($user, "score_sets")) {
		my @selected = $r->param('selectedSet');
		if (@selected) {
			print CGI::p("All of these files will also be made available for mail merge");
		} 
		foreach my $setID (@selected) {
	
			my @validFiles;
			foreach my $type ("scr", "ful") {
				my $filename = "s$setID$type.csv";
				my $path = "$scoringDir/$filename";
				push @validFiles, $filename if -f $path;
			}
			if (@validFiles) {
				print CGI::h2("$setID");
				foreach my $filename (@validFiles) {
					#print CGI::a({href=>"../scoringDownload/?getFile=${filename}&".$self->url_authen_args}, $filename);
					print CGI::a({href=>$self->systemLink($scoringDownloadPage,
					               params=>{getFile => $filename } )}, $filename);
					print CGI::br();
				}
				print CGI::hr();
			}
		}
		if (-f "$scoringDir/$scoringFileName") {
			print CGI::h2("Totals");
			#print CGI::a({href=>"../scoringDownload/?getFile=${courseName}_totals.csv&".$self->url_authen_args}, "${courseName}_totals.csv");
			print CGI::a({href=>$self->systemLink($scoringDownloadPage,
					               params=>{getFile => "$scoringFileName" } )}, "$scoringFileName");
			print CGI::hr();
			print CGI::pre({style=>'font-size:smaller'},WeBWorK::Utils::readFile("$scoringDir/$scoringFileName"));
		}
	}
	
	return "";
}

# If, some day, it becomes possible to assign a different number of problems to each student, this code
# will have to be rewritten some.
# $format can be any of "normal", "full", "everything", "info", or "totals".  An undefined value defaults to "normal"
#   normal: student info, the status of each problem in the set, and a "totals" column
#   full: student info, the status of each problem, and the number of correct and incorrect attempts
#   everything: "full" plus a totals column
#   info: student info columns only
#   totals: total column only
sub scoreSet {
	my ($self, $setID, $format, $showIndex, $UsersRef, $sortedUserIDsRef) = @_;
	my $r  = $self->r;
	my $db = $r->db;
	my @scoringData;
	my $scoringItems   = {    info             => 0,
		                      successIndex     => 0,
		                      setTotals        => 0,
		                      problemScores    => 0,
		                      problemAttempts  => 0, 
		                      header           => 0,
	};
	$format = "normal" unless defined $format;
	$format = "normal" unless $format eq "full" or $format eq "everything" or $format eq "totals" or $format eq "info";
	my $columnsPerProblem = ($format eq "full" or $format eq "everything") ? 3 : 1;
	
	my $setRecord = $db->getGlobalSet($setID); #checked
	die "global set $setID not found. " unless $setRecord;
	#my %users;
	#my %userStudentID=();
	#$WeBWorK::timer->continue("Begin getting users for set $setID") if defined($WeBWorK::timer);
	#foreach my $userID ($db->listUsers()) {
	#	my $userRecord = $db->getUser($userID); # checked
	#	die "user record for $userID not found" unless $userID;
	#	# FIXME: if two users have the same student ID, the second one will
	#	# clobber the first one. this is bad!
	#	# The key is what we'd like to sort by.
	#	$users{$userRecord->student_id} = $userRecord;
	#	$userStudentID{$userID} = $userRecord->student_id;
	#}
	#$WeBWorK::timer->continue("End getting users for set $setID") if defined($WeBWorK::timer);	
	
	my %Users = %$UsersRef; # user objects hashed on user ID
	my @sortedUserIDs = @$sortedUserIDsRef; # user IDs sorted by student ID
	
	my @problemIDs = $db->listGlobalProblems($setID);

	# determine what information will be returned
	if ($format eq 'normal') {
		$scoringItems  = {    info             => 1,
		                      successIndex     => $showIndex,
		                      setTotals        => 1,
		                      problemScores    => 1,
		                      problemAttempts  => 0, 
		                      header           => 1,
		};
	} elsif ($format eq 'full') {
		$scoringItems  = {    info             => 1,
		                      successIndex     => $showIndex,
		                      setTotals        => 0,
		                      problemScores    => 1,
		                      problemAttempts  => 1, 
		                      header           => 1,
		};
	} elsif ($format eq 'everything') {
		$scoringItems  = {    info             => 1,
		                      successIndex     => $showIndex,
		                      setTotals        => 1,
		                      problemScores    => 1,
		                      problemAttempts  => 1, 
		                      header           => 1,
		};
	} elsif ($format eq 'totals') {
		$scoringItems  = {    info             => 0,
		                      successIndex     => $showIndex,
		                      setTotals        => 1,
		                      problemScores    => 0,
		                      problemAttempts  => 0, 
		                      header           => 0,
		};
	} elsif ($format eq 'info') {
		$scoringItems  = {    info             => 0,
		                      successIndex     => 0,
		                      setTotals        => 0,
		                      problemScores    => 0,
		                      problemAttempts  => 0, 
		                      header           => 1,
		};
	} else {
		warn "unrecognized format";
	}
	
	# Initialize a two-dimensional array of the proper size
	for (my $i = 0; $i < @sortedUserIDs + 7; $i++) { # 7 is how many descriptive fields there are in each column
		push @scoringData, [];
	}
	
	#my @userKeys = sort keys %users; # list of "student IDs" NOT user IDs
	
	if ($scoringItems->{header}) {
		$scoringData[0][0] = "NO OF FIELDS";
		$scoringData[1][0] = "SET NAME";
		$scoringData[2][0] = "PROB NUMBER";
		$scoringData[3][0] = "DUE DATE";
		$scoringData[4][0] = "DUE TIME";
		$scoringData[5][0] = "PROB VALUE";

	
	
	# Write identifying information about the users

		for (my $field=0; $field < @userInfoFields; $field++) {
			if ($field > 0) {
				for (my $i = 0; $i < 6; $i++) {
					$scoringData[$i][$field] = "";
				}
			}
			$scoringData[6][$field] = $userInfoColumnHeadings[$field];
			for (my $user = 0; $user < @sortedUserIDs; $user++) {
				my $fieldName = $userInfoFields[$field];
				$scoringData[$user + 7][$field] = $Users{$sortedUserIDs[$user]}->$fieldName;
			}
		}
	}
	return @scoringData if $format eq "info";
	
	# pre-fetch global problems
	$WeBWorK::timer->continue("pre-fetching global problems for set $setID") if defined($WeBWorK::timer);
	my %GlobalProblems = map { $_->problem_id => $_ }
		$db->getAllGlobalProblems($setID);
	$WeBWorK::timer->continue("done pre-fetching global problems for set $setID") if defined($WeBWorK::timer);
	
	# pre-fetch user problems
	$WeBWorK::timer->continue("pre-fetching user problems for set $setID") if defined($WeBWorK::timer);
	my %UserProblems; # $UserProblems{$userID}{$problemID}
	foreach my $userID (@sortedUserIDs) {
		my %CurrUserProblems = map { $_->problem_id => $_ }
			$db->getAllUserProblems($userID, $setID);
		$UserProblems{$userID} = \%CurrUserProblems;
	}
	$WeBWorK::timer->continue("done pre-fetching user problems for set $setID") if defined($WeBWorK::timer);
	
	# Write the problem data
	my $dueDateString = $self->formatDateTime($setRecord->due_date);
	my ($dueDate, $dueTime) = $dueDateString =~ m/^([^\s]*)\s*([^\s]*)$/;
	my $valueTotal = 0;
	my %userStatusTotals = ();
	my %userSuccessIndex = ();
	my %numberOfAttempts = ();
	my $num_of_problems  = @problemIDs;
	for (my $problem = 0; $problem < @problemIDs; $problem++) {
		
		#my $globalProblem = $db->getGlobalProblem($setID, $problemIDs[$problem]); #checked
		my $globalProblem = $GlobalProblems{$problemIDs[$problem]};
		die "global problem $problemIDs[$problem] not found for set $setID" unless $globalProblem;
		
		my $column = 5 + $problem * $columnsPerProblem;
		if ($scoringItems->{header}) {
			$scoringData[0][$column] = "";
			$scoringData[1][$column] = $setRecord->set_id;
			$scoringData[2][$column] = $globalProblem->problem_id;
			$scoringData[3][$column] = $dueDate;
			$scoringData[4][$column] = $dueTime;
			$scoringData[5][$column] = $globalProblem->value;
			$scoringData[6][$column] = "STATUS";
			if ($scoringItems->{header} and $scoringItems->{problemAttempts}) { # Fill in with blanks, or maybe the problem number
				for (my $row = 0; $row < 6; $row++) {
					for (my $col = $column+1; $col <= $column + 2; $col++) {
						if ($row == 2) {
							$scoringData[$row][$col] = $globalProblem->problem_id;
						} else {
							$scoringData[$row][$col] = "";
						}
					}
				}
				$scoringData[6][$column + 1] = "#corr";
				$scoringData[6][$column + 2] = "#incorr";
			}
		}
		$valueTotal += $globalProblem->value;
		
		
		for (my $user = 0; $user < @sortedUserIDs; $user++) {
			#my $userProblem = $userProblems{    $users{$userKeys[$user]}->user_id   };
			#my $userProblem = $UserProblems{$sers{$userKeys[$user]}->user_id}{$problemIDs[$problem]};
			my $userProblem = $UserProblems{$sortedUserIDs[$user]}{$problemIDs[$problem]};
			unless (defined $userProblem) { # assume an empty problem record if the problem isn't assigned to this user
				$userProblem = $db->newUserProblem;
				$userProblem->status(0);
				$userProblem->value(0);
				$userProblem->num_correct(0);
				$userProblem->num_incorrect(0);
			}
			$userStatusTotals{$user} = 0 unless exists $userStatusTotals{$user};
			my $user_problem_status          = ($userProblem->status =~/^[\d\.]+$/) ? $userProblem->status : 0; # ensure it's numeric
			$userStatusTotals{$user}        += $user_problem_status * $globalProblem->value;	
			if ($scoringItems->{successIndex})   {
				$numberOfAttempts{$user}  = 0 unless defined($numberOfAttempts{$user});
				my $num_correct     = $userProblem->num_correct;
				my $num_incorrect   = $userProblem->num_incorrect;
				$num_correct        = ( defined($num_correct) and $num_correct) ? $num_correct : 0;
				$num_incorrect      = ( defined($num_incorrect) and $num_incorrect) ? $num_incorrect : 0;
				$numberOfAttempts{$user} += $num_correct + $num_incorrect;	 
			}
			if ($scoringItems->{problemScores}) {
				$scoringData[7 + $user][$column] = $userProblem->status;
				if ($scoringItems->{problemAttempts}) {
					$scoringData[7 + $user][$column + 1] = $userProblem->num_correct;
					$scoringData[7 + $user][$column + 2] = $userProblem->num_incorrect;
				}
			}
		}
	}
	if ($scoringItems->{successIndex}) {
		for (my $user = 0; $user < @sortedUserIDs; $user++) {
			my $avg_num_attempts = ($num_of_problems) ? $numberOfAttempts{$user}/$num_of_problems : 0;
			$userSuccessIndex{$user} = ($avg_num_attempts) ? ($userStatusTotals{$user}/$valueTotal)**2/$avg_num_attempts : 0;						
		}
	}
	# write the status totals
	if ($scoringItems->{setTotals}) { # Ironic, isn't it?
		my $totalsColumn = $format eq "totals" ? 0 : 5 + @problemIDs * $columnsPerProblem;
		$scoringData[0][$totalsColumn]    = "";
		$scoringData[1][$totalsColumn]    = $setRecord->set_id;
		$scoringData[2][$totalsColumn]    = "";
		$scoringData[3][$totalsColumn]    = "";
		$scoringData[4][$totalsColumn]    = "";
		$scoringData[5][$totalsColumn]    = $valueTotal;
		$scoringData[6][$totalsColumn]    = "total";
		if ($scoringItems->{successIndex}) {
			$scoringData[0][$totalsColumn+1]    = "";
			$scoringData[1][$totalsColumn+1]    = $setRecord->set_id;
			$scoringData[2][$totalsColumn+1]    = "";
			$scoringData[3][$totalsColumn+1]    = "";
			$scoringData[4][$totalsColumn+1]    = "";
			$scoringData[5][$totalsColumn+1]    = '100';
			$scoringData[6][$totalsColumn+1]  = "index" ;
		}
		for (my $user = 0; $user < @sortedUserIDs; $user++) {
            $userStatusTotals{$user} =$userStatusTotals{$user} ||0;
			$scoringData[7+$user][$totalsColumn] = sprintf("%.1f",$userStatusTotals{$user}) if $scoringItems->{setTotals};
			$scoringData[7+$user][$totalsColumn+1] = sprintf("%.0f",100*$userSuccessIndex{$user}) if $scoringItems->{successIndex};

		}
	}
	$WeBWorK::timer->continue("End  set $setID") if defined($WeBWorK::timer);
	return @scoringData;
}

sub sumScores {    # Create a totals column for each student
	my $self        = shift;
	my $r_totals    = shift;
	my $showIndex   = shift;
	my $r_users     = shift;
	my $r_sorted_user_ids =shift;
	my $r           = $self->r;
	my $db          = $r->db;
	my @scoringData = ();
	my $index_increment  = ($showIndex) ? 2 : 1;
	# This whole thing is a hack, but here goes.  We're going to sum the appropriate columns of the totals file:
	# I believe we have $r_totals->[rows]->[cols]  -- the way it's printed out.
	my $start_column  = 6;  #The problem column 
	my $last_column   = $#{$r_totals->[1]};  # try to figure out the number of the last column in the array.
	my $row_count     = $#{$r_totals};
	
	# Calculate total number of problems for the course.
	my $totalPoints      = 0;
	my $problemValueRow  = 5;
	for( my $j = $start_column;$j<=$last_column;$j+= $index_increment) {
		my $score = $r_totals->[$problemValueRow]->[$j];
		$totalPoints += ($score =~/^\s*[\d\.]+\s*$/)? $score : 0;
	}
    foreach my $i (0..$row_count) {
    	my $studentTotal = 0;
		for( my $j = $start_column;$j<=$last_column;$j+= $index_increment) {
			my $score = $r_totals->[$i]->[$j];
			$studentTotal += ($score =~/^\s*[\d\.]+\s*$/)? $score : 0;
			
		}
		$scoringData[$i][0] =sprintf("%.1f",$studentTotal);
		$scoringData[$i][1] =($totalPoints) ?sprintf("%.1f",100*$studentTotal/$totalPoints) : 0;
    }
    $scoringData[0]      = ['',''];
    $scoringData[1]      = ['summary', '%score'];
	$scoringData[2]      = ['',''];
	$scoringData[3]      = ['',''];
	$scoringData[4]      = ['',''];
	$scoringData[6]      = ['',''];


	return @scoringData;
}


# Often it's more efficient to just get everything out of the database
# and then pick out what you want later.  Hence, these "everything2*" functions
sub everything2info {
	my ($self, @everything) = @_;
	my @result = ();
	foreach my $row (@everything) {
		push @result, [@{$row}[0..4]];
	}
	return @result;
}

sub everything2normal {
	my ($self, @everything) = @_;
	my @result = ();
	foreach my $row (@everything) {
		my @row = @$row;
		my @newRow = ();
		push @newRow, @row[0..4];
		for (my $i = 5; $i < @row; $i+=3) {
			push @newRow, $row[$i];
		}
		#push @newRow, $row[$#row];
		push @result, [@newRow];
	}
	return @result;
}

sub everything2full {
	my ($self, @everything) = @_;
	my @result = ();
	foreach my $row (@everything) {
		push @result, [@{$row}[0..($#{$row}-1)]];
	}
	return @result;
}

sub everything2totals {
	my ($self, @everything) = @_;
	my @result = ();
	foreach my $row (@everything) {
		push @result, [${$row}[$#{$row}]];
	}
	return @result;
}

sub appendColumns {
	my ($self, $a1, $a2) = @_;
	my @a1 = @$a1;
	my @a2 = @$a2;
	for (my $i = 0; $i < @a1; $i++) {
		push @{$a1[$i]}, @{$a2[$i]};
	}
}

# Reads a CSV file and returns an array of arrayrefs, each containing a
# row of data:
# (["c1r1", "c1r2", "c1r3"], ["c2r1", "c2r2", "c2r3"])
sub readCSV {
	my ($self, $fileName) = @_;
	my @result = ();
	my @rows = split m/\n/, readFile($fileName);
	foreach my $row (@rows) {
		push @result, [split m/\s*,\s*/, $row];
	}
	return @result;
}

# Write a CSV file from an array in the same format that readCSV produces
sub writeCSV {
	my ($self, $filename, @csv) = @_;
	
	my @lengths = ();
	for (my $row = 0; $row < @csv; $row++) {
		for (my $column = 0; $column < @{$csv[$row]}; $column++) {
			$lengths[$column] = 0 unless defined $lengths[$column];
			$lengths[$column] = length $csv[$row][$column] if defined($csv[$row][$column]) and length $csv[$row][$column] > $lengths[$column];
		}
	}
	
	# Before writing a new totals file, we back up an existing totals file keeping any previous backups.
	# We do not backup any other type of scoring files (e.g. ful or scr).
	
	if (($filename =~ m|(.*)/(.*_totals)\.csv$|) and (-e $filename)) {
		my $scoringDir = $1;
		my $short_filename = $2;
		my $i=1;
		while(-e "${scoringDir}/${short_filename}_bak$i.csv") {$i++;}      #don't overwrite existing backups
		my $bakFileName ="${scoringDir}/${short_filename}_bak$i.csv";
		rename $filename, $bakFileName or warn "Unable to rename $filename to $bakFileName";
	}

	open my $fh, ">", $filename or warn "Unable to open $filename for writing";
	foreach my $row (@csv) {
		my @rowPadded = ();
		foreach (my $column = 0; $column < @$row; $column++) {
			push @rowPadded, $self->pad($row->[$column], $lengths[$column] + 1);
		}
		print $fh join(",", @rowPadded);
		print $fh "\n";
	}
	close $fh;
}

# As soon as backwards compatability is no longer a concern and we don't expect to have
# to use old ww1.x code to read the output anymore, I recommend switching to using
# these routines, which are more versatile and compatable with other programs which
# deal with CSV files.
sub readStandardCSV {
	my ($self, $fileName) = @_;
	my @result = ();
	my @rows = split m/\n/, readFile($fileName);
	foreach my $row (@rows) {
		push @result, [$self->splitQuoted($row)];
	}
	return @result;
}

sub writeStandardCSV {
	my ($self, $filename, @csv) = @_;
	open my $fh, ">", $filename;
	foreach my $row (@csv) {
		print $fh (join ",", map {$self->quote($_)} @$row);
		print $fh "\n";
	}
	close $fh;
}

###

# This particular unquote method unquotes (optionally) quoted strings in the
# traditional CSV style (double-quote for literal quote, etc.)
sub unquote {
	my ($self, $string) = @_;
	if ($string =~ m/^"(.*)"$/) {
		$string = $1;
		$string =~ s/""/"/;
	}
	return $string;
}

# Should you wish to treat whitespace differently, this routine has been designed
# to make it easy to do so.
sub splitQuoted {
	my ($self, $string) = @_;
	my ($leadingSpace, $preText, $quoted, $postText, $trailingSpace, $result);
	my @result = ();
	my $continue = 1;
	while ($continue) {
		$string =~ m/\G(\s*)/gc;
		$leadingSpace = $1;
		$string =~ m/\G([^",]*)/gc;
		$preText = $1;
		if ($string =~ m/\G"((?:[^"]|"")*)"/gc) {
			$quoted = $1;
		}
		$string =~ m/\G([^,]*?)(\s*)(,?)/gc;
		($postText, $trailingSpace, $continue) = ($1, $2, $3);

		$preText = "" unless defined $preText;
		$postText = "" unless defined $postText;
		$quoted = "" unless defined $quoted;

		if ($quoted and (not $preText and not $postText)) {
				$quoted =~ s/""/"/;
				$result = $quoted;
		} else {
			$result = "$preText$quoted$postText";
		}
		push @result, $result;
	}
	return @result;
}

# This particular quoting method does CSV-style (double a quote to escape it) quoting when necessary.
sub quote {
	my ($self, $string) = @_;
	if ($string =~ m/[", ]/) {
		$string =~ s/"/""/;
		$string = "\"$string\"";
	}
	return $string;
}

sub pad {
	my ($self, $string, $padTo) = @_;
	$string = '' unless defined $string;
	return $string unless $self->{padFields}==1;
	my $spaces = $padTo - length $string;

#	return " "x$spaces.$string;
	return $string." "x$spaces;
}

sub maxLength {
	my ($self, $arrayRef) = @_;
	my $max = 0;
	foreach my $cell (@$arrayRef) {
		$max = length $cell unless length $cell < $max;
	}
	return $max;
}

sub popup_set_form {
	my $self  = shift;
	my $r     = $self->r;	
	my $db    = $r->db;
	my $ce    = $r->ce;
	my $authz = $r->authz;
	my $user  = $r->param('user');

	my $root = $ce->{webworkURLs}->{root};
	my $courseName = $ce->{courseName};

 #     return CGI::em("You are not authorized to access the Instructor tools.") unless $authz->hasPermissions($user, "access_instructor_tools");

	# This code will require changing if the permission and user tables ever have different keys.
    my @setNames              = ();
	my $ra_set_records        = $self->{ra_set_records};
	my %setLabels             = ();#  %$hr_classlistLabels;
	my @set_records           =  sort {$a->set_id cmp $b->set_id } @{$ra_set_records};
	foreach my $sr (@set_records) {
 		$setLabels{$sr->set_id} = $sr->set_id;
 		push(@setNames, $sr->set_id);  # reorder sets
	}
 	return 			CGI::popup_menu(-name=>'selectedSet',
 							   -values=>\@setNames,
 							   -labels=>\%setLabels,
 							   -size  => 10,
 							   -multiple => 1,
 							   #-default=>$user
 					),


}
1;
