#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

use strict;
use F4DE_TestCore;
use MMisc;

my $tool = shift @ARGV;
MMisc::error_quit("ERROR: Tool ($tool) empty or not an executable\n")
  if ((MMisc::is_blank($tool)) || (! MMisc::is_file_x($tool)));
my $mode = shift @ARGV;

print "** Running MTest tests: mode=$mode\n";

my $mmk = F4DE_TestCore::get_magicmode_comp_key();

my $totest = 0;
my $testr = 0;
my $tn = "";

#my $trial_metric_add = "-u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -G -b Color";

my $trial_metric_add = "";

my $t0 = F4DE_TestCore::get_currenttime();

my $com = "";

#-s expid.detection.csv:detection -s expid.threshold.csv:threshold expid_TrialIndex.csv:TrialIndex -J expid_join.sql

### Test 1
$tn = "test1";
$com =  "-t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.oneSys.ref.csv -s MTest.oneSys.sys.csv -F SQL_filter_1block.sql";
$testr += &do_less_simple_test($tn, "One system file, trial weighted", $com, "res-$tn.txt");

### Test 2
$tn = "test2";
$com =  "-t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.oneSys.ref.csv -s MTest.oneSys.sys.csv -F SQL_filter_Nblock.sql MTest.oneSys.metadata.csv:metadata";
$testr += &do_less_simple_test($tn, "One system file, block differentiated, trial weighted", $com, "res-$tn.txt");

### Test 2d
$tn = "test2d";
$com =  "--dividedSys SQL_DeriveSystem.sql -J SQL_thresholdTable.sql -t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.derivSys.ref.csv -s MTest.derivSys.sys.detect.csv:detection -s MTest.derivSys.sys.thresh.csv:threshold -F SQL_filter_Nblock.sql  MTest.derivSys.metadata.csv:metadata" ;
$testr += &do_less_simple_test($tn, "Derived system file, block differentiated, trial weighted", $com, "res-$tn.txt");

### Test 3
$tn = "test3";
$com =  "--BlockAverage -t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.oneSys.ref.csv -s MTest.oneSys.sys.csv -F SQL_filter_Nblock.sql MTest.oneSys.metadata.csv:metadata";
$testr += &do_less_simple_test($tn, "One system file, block differentiated, block weighted", $com, "res-$tn.txt");

### Test 3d
$tn = "test3d";
#$com =  "--BlockAverage --dividedSys SQL_DeriveSystem.sql -J SQL_thresholdTable.sql -t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.derivSys.ref.csv -s MTest.derivSys.sys.detect.csv:detection -s MTest.derivSys.sys.thresh.csv:threshold -F SQL_filter_Nblock.sql  MTest.derivSys.metadata.csv:metadata" ;
$com =  "--BlockAverage --dividedSys SQL_DeriveSystem.sql -j 0.5 -t IndividualColorDetection -u MetricNormLinearCostFunct -U CostMiss=1 -U CostFA=1 -U Ptarg=0.5 -r MTest.derivSys.ref.csv -s MTest.derivSys.sys.detect.csv:detection -s MTest.derivSys.sys.thresh.csv:threshold -F SQL_filter_Nblock.sql  MTest.derivSys.metadata.csv:metadata" ;
$testr += &do_less_simple_test($tn, "Derived system file, block differentiated, block weighted", $com, "res-$tn.txt");

#####

my $elapsed = F4DE_TestCore::get_elapsedtime($t0);
my $add = "";
$add .= " [Elapsed: $elapsed seconds]" if (F4DE_TestCore::is_elapsedtime_on());

MMisc::ok_quit("All test ok$add\n")
  if ($testr == $totest);

MMisc::error_quit("Not all test ok$add\n");

##########

sub do_simple_test {
  my ($testname, $subtype, $command, $res, $rev) = 
    MMisc::iuav(\@_, "", "", "", "", 0);

  $totest++;

  return(F4DE_TestCore::run_simpletest($testname, $subtype, $command, $res, $mode, $rev));
}

#####

sub do_less_simple_test {
  my ($testname, $subtype, $cadd, $res, $rev) = 
    MMisc::iuav(\@_, "", "", "", "", 0);
  
  my $tdir = "$res.dir";
  `rm -rf $tdir` if (-e $tdir); # Erase the previous one if present

  MMisc::error_quit("Could not make temporary dir for testing ($tdir)")
    if (! MMisc::make_wdir($tdir));
  
  my $command = "$tool -o $tdir $cadd $trial_metric_add ; cat $tdir/scoreDB.scores.txt";

  my $retval = &do_simple_test($testname, $subtype, $command, $res, $rev);

  if ($mode eq $mmk) {
    print "  (keeping: $tdir)\n";
  } else {
#   `rm -rf $tdir`;
  }

  return($retval);
}

##########

sub do_skip_test {
  my ($testname, $subtype, $cadd1, $res, $cadd2, $rev) = 
    MMisc::iuav(\@_, "", "", "", "", "", 0);
  
  my $tdir = "/tmp/DEVA_cli_tester-Temp_$testname";
  `rm -rf $tdir` if (-e $tdir); # Erase the previous one if present
  MMisc::error_quit("Could not make temporary dir for testing ($tdir)")
    if (! MMisc::make_wdir($tdir));
  
  my $tdir1 = "$tdir/step1";
  MMisc::error_quit("Could not make temporary dir for testing ($tdir1)")
    if (! MMisc::make_wdir($tdir1));

  my $tdir2 = "$tdir/step2";
  MMisc::error_quit("Could not make temporary dir for testing ($tdir2)")
    if (! MMisc::make_wdir($tdir2));

  my $command = "$tool -o $tdir1 $cadd1 $trial_metric_add";

  my $retval = &do_simple_test($testname, "$subtype [step1]", $command, $res . "-step1", $rev);

#  my $db = "$tdir1/scoreDB.db";
#  $retval += &do_simple_test($testname, "$subtype [step1 DBcheck]", "sqlite3 $db < add_checker.sql", $res . "-step1_DBcheck", $rev);
#
#  $command = "$tool -c -C -R $tdir1/referenceDB.db -S $tdir1/systemDB.db -o $tdir2 $cadd2 $trial_metric_add";
#
#  $retval += &do_simple_test($testname, "$subtype [step2]", $command, $res . "-step2", $rev);
#
#  $db = "$tdir2/scoreDB.db";
#  $retval += &do_simple_test($testname, "$subtype [step2 DBcheck]", "sqlite3 $db < add_checker.sql", $res . "-step2_DBcheck", $rev);

  if ($mode eq $mmk) {
    print "  (keeping: $tdir)\n";
  } else {
#    `rm -rf $tdir`;
  }

  return($retval);
}