#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#

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

my $dir = "../../../DEVA/test/MTests/";

### Test 2m13a
$tn = "test2m13a";
$com =  "-p MED13ALADDIN -r $dir/MTest.derivSys.ref.csv -s $dir/MTest.derivSys.sys.detect.csv:detection -s $dir/MTest.derivSys.med13.sys.thresh.csv:threshold $dir/MTest.derivSys.sys.index.csv:TrialIndex" ;
$testr += &do_less_simple_test($tn, "MED13 Profile, Derived system file, block differentiated, trial weighted", $com, "res-$tn.txt");

### Test 2m14
$tn = "test2m14";
$com =  "-p MED14 -r $dir/MTest.derivSys.ref.csv -s $dir/MTest.derivSys.med14.sys.detect.csv:detection -s $dir/MTest.derivSys.med14.sys.thresh.csv:threshold $dir/MTest.derivSys.sys.index.csv:TrialIndex" ;
$testr += &do_less_simple_test($tn, "MED14 Profile, Rank Sorting, Derived system file, block differentiated, trial weighted", $com, "res-$tn.txt");


#####

my $elapsed = F4DE_TestCore::get_elapsedtime($t0);
my $add = "";
$add .= " [Elapsed: $elapsed seconds]" if (F4DE_TestCore::is_elapsedtime_on());

MMisc::ok_quit("All test ok$add\n")
  if ($testr == $totest/2);

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
  
  my $command = "../../../DEVA/tools/DEVA_cli/DEVA_cli.pl -o $tdir $cadd $trial_metric_add ; cat $tdir/scoreDB.scores.txt";
  my $retval = &do_simple_test($testname, $subtype, $command, $res, $rev);

  if ($retval == 1){
    print "  Phase 1 passed: Starting Phase 2\n"; print "  ";
    $command = "../../tools/APDump/APDump.pl  -o - -c Eval=evl -c Run=first $tdir/*srl.gz";
    $retval = &do_simple_test($testname."-apd", "APDump for ".$subtype, $command, "res-$testname-apd.txt", $rev);

  }

  if ($mode eq $mmk) {
    print "  (keeping: $tdir)\n";
  } else {
    `rm -rf $tdir`;
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
