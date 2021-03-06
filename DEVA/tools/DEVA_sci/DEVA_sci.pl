#!/bin/sh
#! -*-perl-*-
eval 'exec env PERL_PERTURB_KEYS=0 PERL_HASH_SEED=0 perl -x -S $0 ${1+"$@"}'
    if 0;

# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#
# DEVA Scoring Interface
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "DEVA_sci" is an experimental system.
# NIST assumes no responsibility whatsoever for its use by any party, and makes no guarantees,
# expressed or implied, about its quality, reliability, or any other characteristic.
#
# We would appreciate acknowledgement if the software is used.  This software can be
# redistributed and/or modified freely provided that any derivative works bear some notice
# that they are derived from it, and any modified versions bear some notice that they
# have been modified.
#
# THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS
# OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY,
# OR FITNESS FOR A PARTICULAR PURPOSE.

use strict;

# Note: Designed for UNIX style environments (ie use cygwin under Windows).

##########
# Check we have every module (perl wise)

my (@f4bv, $f4d);
BEGIN {
  if ( ($^V ge 5.18.0)
       && ( (! exists $ENV{PERL_HASH_SEED})
	    || ($ENV{PERL_HASH_SEED} != 0)
	    || (! exists $ENV{PERL_PERTURB_KEYS} )
	    || ($ENV{PERL_PERTURB_KEYS} != 0) )
     ) {
    print "You are using a version of perl above 5.16 ($^V); you need to run perl as:\nPERL_PERTURB_KEYS=0 PERL_HASH_SEED=0 perl\n";
    exit 1;
  }

  use Cwd 'abs_path';
  use File::Basename 'dirname';
  $f4d = dirname(abs_path($0));

  push @f4bv, ("$f4d/../../../common/lib");
}
use lib (@f4bv);

sub eo2pe {
  my $oe = join(" ", @_);
  return( ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "");
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files.";
my $warn_msg = "";
sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

# Part of this tool
foreach my $pn ("MMisc", "CSVHelper", "MtSQLite", "DETCurve", "DETCurveSet") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}
my $versionkey = MMisc::slurp_file(dirname(abs_path($0)) . "/../../../.f4de_version");
my $versionid = "DEVA Scoring Interface ($versionkey)";

# usualy part of the Perl Core
foreach my $pn ("Getopt::Long") {
  unless (eval "use $pn; 1") {
    &_warn_add("\"$pn\" is not available on your Perl installation. ", "Please look it up on CPAN [http://search.cpan.org/]\n");
    $have_everything = 0;
  }
}

# Something missing ? Abort
if (! $have_everything) {
  print "\n$warn_msg\nERROR: Some Perl Modules are missing, aborting\n";
  exit(1);
}

# Use the long mode of Getopt
Getopt::Long::Configure(qw(auto_abbrev no_ignore_case));

########################################
# Options processing


# Default values for variables
#
my $refDBtable = 'Reference';
my $refDBfile = '';
my $refDBname = 'referenceDB';
my $sysDBfile = '';
my $sysDBtable = 'System';
my $sysDBname = 'systemDB';
my @resDBfiles = ();
my $resDBname = 'resultsDB';
#
my $mdDBfile = '';
my $mdDBname = "metadataDB";

my $tablename = 'resultsTable';
my $TrialIDcolumn = 'TrialID';
my $BlockIDcolumn = 'BlockID';
my $Targcolumn = 'Targ';
my $Decisioncolumn = 'Decision';
my $Scorecolumn = 'Score';
#
my $TrialsDB = 'TrialsDB';
my $ThreshDB = 'ThresholdTable';
my $Threshcolumn = 'Threshold';

my $bDETf = "DET";

my @ok_modes = ("AND", "OR"); # order is important
my $mode = $ok_modes[0];

my $metric = "MetricNormLinearCostFunct";
my %metparams = ();
my %trialsparams = ();
my $listparams = 0;

my $devadetname = "Block";
my $taskName = "Detection";
my @ok_scales = ('nd', 'log', 'linear'); # order is important
my ($xm, $xM, $ym, $yM, $xscale, $yscale)
  = (0.1, 95, 0.1, 95, $ok_scales[0], $ok_scales[0]);

my $blockavg = 0;
my $GetTrialsDB = 0;
my $decThr = undef;
my $pbid_dt_sql = "";

my @isolinecoef = ();
my @dilc = ( );

my $useRank = 0;

my $supressMetricScores = 0;

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:  B D  G    LM    RSTU  XY  b d   hij lm op rstuv xy   #

my $usage = &set_usage();
my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'ResultDBfile=s'     => \@resDBfiles,
   'referenceDBfile=s'  => \$refDBfile,
   'systemDBfile=s'     => \$sysDBfile,
   'operator=s'         => \$mode,
   'DETfile=s'      => \$bDETf,
   'metricPackage=s'    => \$metric,
   'MetricParameters=s' => \%metparams,
   'TrialsParameters=s' => \%trialsparams,
   'listParameters'     => \$listparams,
   'blockName=s'        => \$devadetname,
   'xmin=f'             => \$xm,
   'Xmax=f'             => \$xM,
   'ymin=f'             => \$ym,
   'Ymax=f'             => \$yM,
   'usedXscale=s'       => \$xscale,
   'UsedYscale=s'       => \$yscale,
   'BlockAverage'       => \$blockavg,
   'taskName=s'         => \$taskName,
   'GetTrialsDB'        => \$GetTrialsDB,
   'decisionThreshold=f' => \$decThr,
   'perBlockDecisionThreshold=s' => \$pbid_dt_sql,
   'LoadMetadataDB=s'   => \$mdDBfile,
   'isolinecoef=s'      => \@isolinecoef,
   'jUseRankForScores'   => \$useRank,
   'SuppressMetricScores' => \$supressMetricScores,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});

MMisc::error_quit("No \'blockName\' specified, aborting")
  if (MMisc::is_blank($devadetname));
MMisc::error_quit("No \'taskName\' specified, aborting")
  if (MMisc::is_blank($taskName));
MMisc::error_quit("No \'metric\' specified, aborting")
  if (MMisc::is_blank($metric));
MMisc::error_quit("Specified \'metric\' does not seem to be using a valid name ($metric), should start with \"Metric\"")
  if (! ($metric =~ m%^metric%i));
unless (eval "use $metric; 1") {
  MMisc::error_quit("Metric package \"$metric\" is not available in your Perl installation. " . &eo2pe($@));
}
my $trialn = $metric;
$trialn =~ s%^Metric%Trials%; # Trial specialized function automatically selected based on selected metric
unless (eval "use $trialn; 1") {
  MMisc::error_quit("Metric package \"$trialn\" is not available in your Perl installation. " . &eo2pe($@));
}

if ($listparams) {
  print "Metric: $metric\n";
  my @lp = ();
  my $lpcmd = "\@lp = $metric\:\:getParamsList()";
  unless (eval "$lpcmd; 1") {
    MMisc::error_quit("Problem obtaining Metric ($metric) parameters (" . join(" ", $@) . ")");
  }
  print "Metric Parameters (" . scalar @lp . "): " . join(", ", @lp) . "\n";

  print "Trials: $trialn\n";
  my @lp = ();
  my $lpcmd = "\@lp = $trialn\:\:getParamsList();";
  unless (eval "$lpcmd; 1") {
    MMisc::error_quit("Problem obtaining Trials ($trialn) parameters (" . join(" ", $@) . ")");
  }
  
  print "Trials Parameters (" . scalar @lp . "): " . join(", ", @lp) . "\n";

  MMisc::ok_quit("");
}

MMisc::error_quit("Invalid value for \'usedXscale\' ($xscale) (possible values: " . join(", ", @ok_scales) . ")")
  if (! grep(m%^$xscale$%, @ok_scales));
MMisc::error_quit("Invalid value for \'UsedYscale\' ($yscale) (possible values: " . join(", ", @ok_scales) . ")")
  if (! grep(m%^$yscale$%, @ok_scales));

my $g_thr = 0;
if ((! MMisc::is_blank($pbid_dt_sql)) && (defined $decThr)) {
  MMisc::warn_print("\'--perBlockDecisionThreshold\' can not be used in conjunction with \'--decisionThreshold\', only using \'--decisionThreshold\'");
  $pbid_dt_sql = "";
}
MMisc::error_quit("\'--perBlockDecisionThreshold\' can not be used in conjunction with \'--BlockAverage\', use \'--decisionThreshold\' instead\n\n$usage")
  if (($pbid_dt_sql) && ($blockavg));
$g_thr = 1 if ((! MMisc::is_blank($pbid_dt_sql)) || (defined $decThr));

MMisc::error_quit("No ScoreDBfile information provided\n\n$usage") 
  if (scalar @ARGV != 1);
MMisc::error_quit("No \'referenceDBfile\' provided\n\n$usage")
  if (MMisc::is_blank($refDBfile));
MMisc::error_quit("No \'systemDBfile\' provided\n\n$usage")
  if (MMisc::is_blank($sysDBfile));
MMisc::error_quit("No \'ResultDBfile\' provided\n\n$usage")
  if (scalar @resDBfiles == 0);
&check_DBs_r($refDBfile, $sysDBfile, @resDBfiles);
&check_DBs_r($mdDBfile) if (! MMisc::is_blank($mdDBfile));
MMisc::error_quit("Unrecognized \'mode\' [$mode], authorized values are: " . join(" ", @ok_modes))
  if (! grep(m%^$mode$%, @ok_modes));

@isolinecoef = split(/,/,join(',',@isolinecoef));
if (scalar @isolinecoef == 0) {
  @isolinecoef = @dilc;
}
foreach my $v (@isolinecoef) {
 MMisc::error_quit("Problem with \'--isolinecoef\' value ($v), does not appear to be a number ?")
   if (! ($v =~ m%^\d+(\.\d+)?$%));
}

my ($dbfile) = @ARGV;

my ($err, $sqlitecmd) = MtSQLite::get_sqlitecmd();
MMisc::error_quit($err)
  if (MMisc::is_blank($sqlitecmd));

my $cmdlines = "";
# Attach the REF and SYS databases
MtSQLite::commandAdd(\$cmdlines, "ATTACH DATABASE \"$refDBfile\" AS $refDBname");
MtSQLite::commandAdd(\$cmdlines, "ATTACH DATABASE \"$sysDBfile\" AS $sysDBname");
my $used_resDBname = "";
my @resDBnames = ();
my %tid2bid = ();
for (my $i = 0; $i < scalar @resDBfiles; $i++) {
  my $resDBfile = $resDBfiles[$i];
  &confirm_table(\%tid2bid, $resDBfile, $tablename, $TrialIDcolumn, $BlockIDcolumn);
  my $lresDBname = $resDBname . sprintf("_%03d", $i);
  MtSQLite::commandAdd(\$cmdlines, "ATTACH DATABASE \"$resDBfile\" AS $lresDBname");
  push @resDBnames, $lresDBname;
}
$used_resDBname = &joinResDBfiles(\$cmdlines, $mode, @resDBnames);

MtSQLite::commandAdd(\$cmdlines, "ATTACH DATABASE \"$mdDBfile\" AS $mdDBname")
  if (! MMisc::is_blank($mdDBfile));

# Create the Final table

## If the rank column is used, it must be added to the table
my $rankCol = "";
$rankCol = ", System.Rank" if ($useRank);

my $tmp=<<EOF
DROP TABLE IF EXISTS main.$refDBtable;
DROP TABLE IF EXISTS main.$sysDBtable;
DROP TABLE IF EXISTS main.$TrialsDB;
DROP TABLE IF EXISTS main.$ThreshDB;

CREATE TABLE $refDBtable AS SELECT $tablename.$TrialIDcolumn,$Targcolumn FROM $used_resDBname.$tablename INNER JOIN $refDBname.$refDBtable WHERE $tablename.$TrialIDcolumn = $refDBtable.$TrialIDcolumn;

CREATE TABLE $sysDBtable AS SELECT $tablename.$TrialIDcolumn,$Decisioncolumn,$Scorecolumn $rankCol FROM $used_resDBname.$tablename INNER JOIN $sysDBname.$sysDBtable WHERE $tablename.$TrialIDcolumn = $sysDBtable.$TrialIDcolumn;

EOF
  ;

$tmp.=<<EOF
CREATE TABLE $TrialsDB AS SELECT $tablename.$TrialIDcolumn,$BlockIDcolumn,$Decisioncolumn,$Scorecolumn,$Targcolumn FROM $used_resDBname.$tablename,$refDBname.$refDBtable,$sysDBname.$sysDBtable WHERE $Targcolumn == 'NOT A VALID VALUE';

EOF
  if ($GetTrialsDB);

if (! MMisc::is_blank($pbid_dt_sql)) {
  my $err = MMisc::check_file_r($pbid_dt_sql);
  MMisc::error_quit("Problem with \'--perBlockDetectionThreshold\' file ($pbid_dt_sql) : $err")
    if (! MMisc::is_blank($err));

  my $includeRanks = 1;

  $tmp .= "CREATE TABLE $ThreshDB ($BlockIDcolumn TEXT PRIMARY KEY, $Threshcolumn REAL".
    ($includeRanks ? ", RankThreshold INT" : "").");\n";

  my $sc = MMisc::slurp_file($pbid_dt_sql);
  MMisc::error_quit("Problem with \'--perBlockDetectionThreshold\' file ($pbid_dt_sql) : empty file ?")
    if ((! defined $sc) || (MMisc::is_blank($sc)));

  $tmp .= $sc;
}

MtSQLite::commandAdd(\$cmdlines, $tmp);
my ($err, $log, $stdout, $stderr) = 
  MtSQLite::sqliteCommands($sqlitecmd, $dbfile, $cmdlines);
MMisc::error_quit($err) if (! MMisc::is_blank($err));

my %ref = ();
&confirm_table(\%ref, $dbfile, $refDBtable, $TrialIDcolumn, $Targcolumn);
my %sys = ();
if (! $useRank){
  &confirm_table(\%sys, $dbfile, $sysDBtable, $TrialIDcolumn, $Decisioncolumn, $Scorecolumn);
} else {
  &confirm_table(\%sys, $dbfile, $sysDBtable, $TrialIDcolumn, $Decisioncolumn, $Scorecolumn, "Rank");
}

my $tot1 = scalar(keys %ref) + scalar(keys %sys);

my %bid_thr = ();
&confirm_table(\%bid_thr, $dbfile, $ThreshDB, $BlockIDcolumn, $Threshcolumn) if (! MMisc::is_blank($pbid_dt_sql));

#print MMisc::get_sorted_MemDump(\%ref);
#print MMisc::get_sorted_MemDump(\%sys);

my ($mapped, $unmapped_sys, $unmapped_ref_targ, $unmapped_ref_nontarg) = (0, 0, 0, 0);

my %bid_trials = ();
my @at = ();
##
my $blockavg_text = "$devadetname Average";
foreach my $key (keys %sys) {
  
  my $bid = (MMisc::safe_exists(\%tid2bid, $key, $BlockIDcolumn)) 
    ? $tid2bid{$key}{$BlockIDcolumn} : $BlockIDcolumn;

  my $ubid = ($blockavg) ? $blockavg_text : $bid;

  &def_bid_trials($ubid, $bid);

  my $decision = ($sys{$key}{$Decisioncolumn} eq 'y') ? 'YES' : 'NO';
  my $istarg   = 0;
  my $sortValue = $key;
  my $score = $sys{$key}{$Scorecolumn};
  if ($useRank){
    $score = -$sys{$key}{"Rank"};
  }

  if (exists $ref{$key}) { # mapped
    $istarg   = ($ref{$key}{$Targcolumn} eq 'y') ? 1 : 0;
    $mapped++;
  } else { # unmapped sys
    $unmapped_sys++;
  }

  if ($g_thr) {
    $bid_trials{$ubid}->addTrialWithoutDecision($bid, $score, $istarg, undef, $sortValue);
  } else {
    $bid_trials{$ubid}->addTrial($bid, $score, $decision, $istarg, undef, $sortValue);
  }
#print "$ubid $istarg $sortValue $g_thr $decision\n" if ($ubid eq "Red");
#  use Data::Dumper;  
#  print "key = $key\nSortvalue = $sortValue\nscore = $score\nisTarg = $istarg\n".
#    Dumper($sys{$key}); 
  push(@at, [$key, $bid, $sys{$key}{$Scorecolumn},
             $decision, ($istarg == 1) ? 'TARG' : 'NonTARG']) if ($GetTrialsDB);
}

foreach my $key (keys %ref) {
  if (! exists $sys{$key}) { # unmapped ref
    my $bid = (MMisc::safe_exists(\%tid2bid, $key, $BlockIDcolumn)) 
      ? $tid2bid{$key}{$BlockIDcolumn} : $BlockIDcolumn;
    my $ubid = ($blockavg) ? $blockavg_text : $bid;
    # If the ref TID is omitted and it is a non-target trial, then it is NOT an error AND it does not get added to the trials, therefore:
    if ($ref{$key}{$Targcolumn} eq 'y') {
      &def_bid_trials($ubid);
      $bid_trials{$ubid}->addTrial($bid, undef, "OMITTED", 1, undef, $key);
      push(@at, [$key, $bid, $sys{$key}{$Scorecolumn}, 'OMITTED', 'TARG']) if ($GetTrialsDB);
      $unmapped_ref_targ++;
    } else {
      $unmapped_ref_nontarg++;
    }
  } 
  
# mapped: already done
}

foreach my $key (sort keys %bid_trials) {
  print "[***** $key]\n";
  print $bid_trials{$key}->dumpCountSummary();
}

print "Mapped              : $mapped\n";
print "UnMapped REF Targ   : $unmapped_ref_targ\n";
print "UnMapped REF NonTarg: $unmapped_ref_nontarg\n";
print "UnMapped SYS: $unmapped_sys\n";

my $tot2 = 2*$mapped + $unmapped_ref_targ + $unmapped_ref_nontarg + $unmapped_sys;
print "Check:\n";
print "-- Total number of entries in REF + SYS                                = $tot1\n";
print "-- 2x mapped + Unmapped REF Targ + Unmapped Ref NonTarg + Unmapped SYS = $tot2\n";
MMisc::error_quit("Problem at check point") if ($tot1 != $tot2);

&add_array2TrialsDB($dbfile, \@at) if (($GetTrialsDB) && (scalar @at > 0));

&doDETwork();

MMisc::ok_quit("Done");

####################

sub add_array2TrialsDB {
  my ($dbfile, $ra) = @_;

  my ($err, $dbh) = MtSQLite::get_dbh($dbfile);
  MMisc::error_quit($err)
    if (! MMisc::is_blank($err));

  my $cmd = "INSERT OR ABORT INTO $TrialsDB ( $TrialIDcolumn, $BlockIDcolumn, $Decisioncolumn, $Scorecolumn, $Targcolumn ) VALUES ( ?, ?, ?, ?, ? )";
  my ($err, $sth) = MtSQLite::get_command_sth($dbh, $cmd);
  MMisc::error_quit("Problem while inserting data into $tablename.$TrialIDcolumn: $err")
    if (! MMisc::is_blank($err));
  foreach my $entry (@$ra) {
    my ($err) = MtSQLite::execute_sth($sth, @$entry);
    MMisc::error_quit("Problem during data insertion into $tablename.$TrialIDcolumn: $err")
      if (! MMisc::is_blank($err));
  }
  my $err = MtSQLite::sth_finish($sth);
  MMisc::error_quit("Problem while completing insertion of data into $tablename.$TrialIDcolumn: $err")
    if (! MMisc::is_blank($err));

  MtSQLite::release_dbh($dbh);
}

##########

sub check_DBs_r {
  for (my $i = 0; $i < scalar @_; $i++) {
    my $fn = $_[$i];
    my $err = MMisc::check_file_r($fn);
    MMisc::error_quit("Problem with DB file [$fn]: $err")
      if (! MMisc::is_blank($err));
  }
}

####################

sub ANDtworesDB {
  my ($rcmd, $in1, $in2, $out) = @_;

  my $tmp=<<EOF
DROP TABLE IF EXISTS $out.$tablename;
CREATE TABLE $out.$tablename AS SELECT $in1.$tablename.$TrialIDcolumn,$in1.$tablename.$BlockIDcolumn FROM $in1.$tablename INNER JOIN $in2.$tablename WHERE $in1.$tablename.$TrialIDcolumn = $in2.$tablename.$TrialIDcolumn;

EOF
  ;

  MtSQLite::commandAdd($rcmd, $tmp);
}

#####

sub ANDresDBs {
  my ($rcmd, @dbl) = @_;

  # We know we have at least 2 tables in the list at this point
  my $in1 = shift @dbl;
  my $in2 = shift @dbl;
  my $jres = "temp.${resDBname}_init";
  &ANDtworesDB($rcmd, $in1, $in2, $jres);
  my $pjres = $jres;
  for (my $i = 0; $i < scalar @dbl; $i++) {
    $jres = "temp.${resDBname}_" . sprint("%04d", $i);
    &ANDtworesDB($rcmd, $pjres, $dbl[$i], $jres);
  }

  return($jres);
}

#####

sub joinResDBfiles {
  my ($rcmd, $mode, @dbl) = @_;

  return($dbl[0]) if (scalar @dbl == 1);

  return(&ANDresDBs($rcmd, @dbl))
    if ($mode eq $ok_modes[0]);

  MMisc::error_quit("Not yet ready mode");
}

####################

sub confirm_table {
  my ($rh, $dbfile, $tablename, @columns) = @_;
  
  my ($err, $count) = MtSQLite::select_helper__to_hash($dbfile, $rh, $tablename, "", @columns);
  MMisc::error_quit($err) if (! MMisc::is_blank($err));
  print "* Extracted from $tablename ${count}x datum\n";
}

####################

sub def_bid_trials {
  my ($ubid, $abid) = @_;

  MMisc::error_quit("Empty BlockID are not authorized")
    if (MMisc::is_blank($ubid));

  return if (exists $bid_trials{$ubid});

  $bid_trials{$ubid} = undef;
  my $trialcmd = "\$bid_trials\{\$ubid\} = new $trialn (\\\%trialsparams, \"$taskName\", \"$devadetname\", \"Trial\");";
  unless (eval "$trialcmd; 1") {
    MMisc::error_quit("Problem creating BlockID ($ubid)'s Trial ($trialn) object (" . join(" ", $@) . ")");
  }
  MMisc::error_quit("Problem with BlockID ($ubid)'s Trial ($trialn)")
    if (! defined $bid_trials{$ubid});

  my $thr = undef;
  $thr = $decThr if (defined $decThr);
  if (! MMisc::is_blank($pbid_dt_sql)) {
    MMisc::error_quit("Could not find BlockID ($abid) in Decision Mapping Table")
      if (! MMisc::safe_exists(\%bid_thr, $abid, $Threshcolumn));
    $thr = $bid_thr{$abid}{$Threshcolumn};
  }
  $bid_trials{$ubid}->setTrialActualDecisionThreshold($thr) if (defined $thr);
#  print "  $ubid $thr $useRank\n";
  $bid_trials{$ubid}->setScoreSort("descending")  if ($useRank);
}

#####

sub doDETwork {
  my $detSet = new DETCurveSet("DET Set");

  foreach my $bid (keys %bid_trials) {
    my $usedtrial = $bid_trials{$bid};
    my $met = undef;
    my $metcmd = "\$met = new $metric (\\\%metparams, \$usedtrial);";
    unless (eval "$metcmd; 1") {
      MMisc::error_quit("Problem creating BlockID ($bid)'s Metric ($metric) object (" . join(" ", $@) . ")");
    }
    MMisc::error_quit("Problem with BlockID ($bid)'s Metric ($metric)")
      if (! defined $met);

    #my $detname = $devadetname . " $bid";
    my $detname = $bid;

    my $det = new DETCurve($usedtrial, $met, $detname, 
                           \@isolinecoef, MMisc::cmd_which("gzip"));

    my $rtn = $detSet->addDET($detname, $det);
    MMisc::error_quit("Error adding DET to the DETSet: $rtn")
      if ($rtn ne "success");
  }

  my $opts = { (xScale => $xscale, yScale => $yscale, 
                Xmin => $xm, Xmax => $xM,
                Ymin => $ym, Ymax => $yM,
                gnuplotPROG => MMisc::cmd_which("gnuplot"),
                serialize => 1,
                createDETfiles => 1,
                BuildPNG => 1 ,
                DETShowPoint_Actual => 1 ),
  };
  if ($supressMetricScores){
    $opts = { (xScale => $xscale, yScale => $yscale, 
               Xmin => $xm, Xmax => $xM,
               Ymin => $ym, Ymax => $yM,
               gnuplotPROG => MMisc::cmd_which("gnuplot"),
               serialize => 1,
               ReportActual => 0,
               ReportBest => 0,
               ExcludeCountsFromReports => 1)
    };
  }

  my $report = $detSet->renderReport($bDETf . ".det", 1, $opts,
                                     ($bDETf eq "" ? "" : $bDETf.".scores.txt"),
                                     "$bDETf.scores.csv",
                                     undef,
                                     undef);
  print $report if ($bDETf eq "");
}

########## 

sub set_usage {
  my $pv = join(", ", @ok_scales);
  my $dilcs = join(",", @dilc);

  my $tmp=<<EOF
$versionid

$0 [--help | --version] --referenceDBfile file --systemDBfile file --ResultDBfile resultsDBfile [--ResultDBfile resultsDBfile [...]] [--LoadMetadataDB file] [--GetTrialsDB] [--metricPackage package] [[--MetricParameters parameter=value] [--MetricParameters parameter=value [...]]] [--TrialsParameters parameter=value [--TrialsParameters parameter=value [...]]] [--listParameters] [--DETfile filebase] [--blockName name] [--taskName name] [--xmin val] [--Xmax val] [--ymin val] [--Ymax val] [--usedXscale set] [--UsedYscale set] [--isolinecoef value[,value[...]]] [--BlockAverage] [--decisionThreshold score | --perBlockDecisionThreshold sql_file] ScoreDBfile

Will load Trials information and create DETcurves

NOTE: will create ScoreDBfile

Where:
  --help     This help message
  --version  Version information
  --referenceDBfile  The Reference SQLite file, loaded as \'$refDBname\' (must contains the 'Reference' table, whose columns are: $TrialIDcolumn, $Targcolumn)
  --systemDBfile     The System SQLite file, loaded as \'$sysDBname\' (must contains the 'System' table, whose columns are: $TrialIDcolumn, $Decisioncolumn, $Scorecolumn)
  --ResultDBfile     The Filter tool resulting DB (must contain the \'$tablename\' table, with the following columns: $TrialIDcolumn, $BlockIDcolumn)
  --LoadMetadataDB   Load the metadata SQLite file, loaded as \'$mdDBname\'
  --GetTrialsDB      Add a table to the scoring database containing each individual Trial component (table name: $TrialsDB)
  --metricPackage    Package to load for metric uses (default: $metric)
  --MetricParameters Metric Package parameters
  --TrialsParameters Trials Package parameters
  --listParameters   List Metric and Trial package authorized parameters
  --DETfile          When working with DET curve, all the relevant files will start with this value (default: $bDETf)
  --blockName        Specify the name of the block type (default: $devadetname)
  --taskName         Specify the name of the task (default: $taskName)
  --xmin --Xmax      Specify the min and max value of the X axis (PFA) of the DET curve (default: $xm and $xM)
  --ymin --Ymax      Specify the min and max value of the Y axis (PMiss) of the DET curve (default: o$ym and $yM)
  --usedXscale --UsedYscale    Specify the scale used for the X and Y axis of the DET curve (Possible values: $pv) (default: $xscale and $yscale)
  --isolinecoef      Specify the iso-line to plot (default: $dilcs)
  --BlockAverage    Combine all Trial in one DET instead of splitting them per BlockID
  --decisionThreshold  When adding a Trial, do not use the System\'s Decision but base the decision on a given threshold
  --perBlockDecisionThreshold  Specify the SQL command file expected to insert into the \'$ThreshDB\' table (with two columns: $BlockIDcolumn $Threshcolumn) a Threshold per BlockID. 
  --jUseRankForScores   Use the ranks supplied in the .detection.csv file rather than the detection scores for computing the DET curves. 
  --SuppressMetricScores Do not report the scores for the specified 'metric'.  The Global metrics will still be produced.


Note: an example of the possible content of a \'--perBlockDecisionThreshold\' sql file can be:
INSERT OR ABORT INTO $ThreshDB ( $BlockIDcolumn, $Threshcolumn ) SELECT threshold.EventID,threshold.DetectionThreshold FROM metadataDB.threshold;

EOF
;

  return($tmp);
}

