#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# KWS Eval Submission Checker
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "KWS Eval Submission Checker" is an experimental system.
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
# Version

# $Id$
my $version     = "0.1b";

if ($version =~ m/b$/) {
  (my $cvs_version = '$Revision$') =~ s/[^\d\.]//g;
  $version = "$version (CVS: $cvs_version)";
}

my $versionid = "KWS Eval Submission Checker Version: $version";

##########
# Check we have every module (perl wise)

## First insure that we add the proper values to @INC
my ($f4b, @f4bv, $f4d);
BEGIN {
  use Cwd 'abs_path';
  use File::Basename 'dirname';
  $f4d = dirname(abs_path($0));

  $f4b = "F4DE_BASE";
  push @f4bv, (exists $ENV{$f4b}) 
    ? ($ENV{$f4b} . "/lib") 
      : ("$f4d/../../lib", "$f4d/../../../common/lib");
}
use lib (@f4bv);

sub eo2pe {
  my @a = @_;
  my $oe = join(" ", @a);
  my $pe = ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "";
  return($pe);
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files. Please check your $f4b environment variable.";
my $warn_msg = "";

# Part of this tool
foreach my $pn ("MMisc") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}

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

my $ecf_ext = '.ecf.xml';
my $tlist_ext = '.tlist.xml';

my $rttm_ext = ".rttm";

my $kwslist_ext = ".kwslist.xml";

my $ValidateKWSList = (exists $ENV{$f4b})
  ? $ENV{$f4b} . "/bin/ValidateKWSList"
  : dirname(abs_path($0)) . "/../ValidateKWSList/ValidateKWSList.pl";

my $usage = &set_usage();
MMisc::error_quit("Usage:\n$usage\n") if (scalar @ARGV == 0);

# Default values for variables
my $verb = 0;
my $qins = 0;
my $specfile = "";
my $outdir = undef;
my @dbDir = ();
my $eteam = undef;
my $scoringReady = 0;

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz #
# Used:                   S  V       d   h  k     q st v     #

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'Verbose'        => \$verb,
   'quit_if_non_scorable' => \$qins,
   'Specfile=s'     => \$specfile,
   'outdir=s'       => \$outdir,
   'dbDir=s'        => \@dbDir,
   'team=s'         => \$eteam,
   'kwslistValidator=s' => \$ValidateKWSList,
   'scoringReady'   => \$scoringReady,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");

MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});

MMisc::error_quit("No arguments left on command line\n\n$usage\n")
  if (scalar @ARGV == 0);

MMisc::error_quit("No \'Specfile\' given, will not continue processing\n\n$usage\n")
  if (MMisc::is_blank($specfile));
my $err = MMisc::check_file_r($specfile);
MMisc::error_quit("Problem with \'Specfile\' ($specfile) : $err")
  if (! MMisc::is_blank($err));

if (defined $outdir) {
  my $de = MMisc::check_dir_w($outdir);
  MMisc::error_quit("Problem with \'outdir\' ($outdir): $de")
    if (! MMisc::is_blank($de));
} else {
  $outdir = MMisc::get_tmpdir();
  MMisc::error_quit("Problem creating temporary directory for \'--outdir\'")
    if (! defined $outdir);
}

$err = MMisc::check_file_x($ValidateKWSList);
MMisc::error_quit("Problem with ValidateKWSList ($ValidateKWSList): $err")
  if (! MMisc::is_blank($err));
MMisc::error_quit("No \'dbDir\' specified, aborting")
  if (scalar @dbDir == 0);
my $tmp = scalar @dbDir;
for (my $i = 0; $i < $tmp; $i++) {
  my $v = shift @dbDir;
  push @dbDir, split(m%\:%, $v);
}
my %ecfs = ();
my %tlists = ();
my %rttms = ();
for (my $i = 0; $i < scalar @dbDir; $i++) {
  $err = MMisc::check_dir_r($dbDir[$i]);
  MMisc::error_quit("Problem with \'dbDir\' (" . $dbDir[$i] . ") : $err")
    if (! MMisc::is_blank($err));
  &obtain_ecf_tlist($dbDir[$i], \%ecfs, \%tlists, \%rttms);
}
MMisc::error_quit("Did not find any ECF or TLIST files; will not be able to continue")
  if ((scalar (keys %ecfs) == 0) || (scalar (keys %tlists) == 0));
&check_ecf_tlist_pairs(\%ecfs, \%tlists, \%rttms);

########################################

# Expected values
my $expid_count = 9;
my @expid_tag;
my @expid_corpus;
my @expid_partition;
my @expid_scase;
my @expid_task;
my @expid_trncond;
my @expid_sysid_beg;

my $tmpstr = MMisc::slurp_file($specfile);
MMisc::error_quit("Problem loading \'Specfile\' ($specfile)")
  if (! defined $tmpstr);
eval $tmpstr;
MMisc::error_quit("Problem during \'SpecFile\' use ($specfile) : " . join(" | ", $@))
  if $@;

sub __cfgcheck {
  my ($t, $v, $c) = @_;
  return if ($c == 0);
  MMisc::error_quit("Missing or improper datum [$t] in \'SpecFile\' ($specfile)")
    if ($v);
}

# EXPID side
&__cfgcheck("\@expid_tag", (scalar @expid_tag == 0), 1);
&__cfgcheck("\@expid_partition", (scalar @expid_partition == 0), 1);
&__cfgcheck("\@expid_scase", (scalar @expid_scase == 0), 1);
&__cfgcheck("\@expid_task", (scalar @expid_task == 0), 1);
&__cfgcheck("\@expid_trncond", (scalar @expid_trncond == 0), 1);
&__cfgcheck("\@expid_sysid_beg", (scalar @expid_sysid_beg == 0), 1);

my $kwsyear = $expid_tag[0];

my $todo = scalar @ARGV;
my $done = 0;
my %warnings = ();
my %notes = ();
my $wn_key = "";
foreach my $sf (@ARGV) {
  %warnings = ();
  %notes = ();

  print "\n---------- [$sf]\n";
  my $ok = 1;

  my ($err) = &check_submission($sf);
  if (! MMisc::is_blank($err)) {
    &valerr($sf, "While checking submission [$sf] : " . $err);
    $ok = 0;
    next;
  }

  if ($ok) {
    &valok($sf, "ok" . &format_warnings_notes());
    $done ++;
  }
}

print "\n\n==========\nAll submission processed (OK: $done / Total: $todo)\n";

MMisc::error_quit("Not all submission processed succesfully")
  if ($done != $todo);
MMisc::ok_quit();

########## END

sub valok {
  my ($fname, $txt) = @_;
  print "$fname: $txt\n";
}

#####

sub valerr {
  my ($fname, $txt) = @_;
  &valok($fname, "[ERROR] $txt");
  &valok($fname, "[ERROR] ** Please refer to the \'Submission Instructions\', in the Appendices of the \'TRECVid Event Detection Evaluation Plan\' for more information");

  MMisc::error_quit("\'quit_if_non_scorable\' selected, quitting")
    if ($qins);
}

#####

sub format_list {
  my $txt = shift @_;
  my $skipbl = shift @_;
  my @list = @_;

  return("$txt None\n")
    if (scalar @list == 0);

  return("$txt " . $list[0] . "\n")
    if (scalar @list == 1);

  my $inc = 1;
  my $out = "$txt (" . scalar @list . ")\n";
  foreach my $entry (@list) {
    $out .= "$skipbl$inc) $entry\n";
    $inc++;
  }

  return($out);
}

#####

sub format_warnings_notes {
  my $txt = "";

  my @todo = keys %notes;
  push @todo, keys %warnings;
  @todo = MMisc::make_array_of_unique_values(\@todo);
  foreach my $key (@todo) {
    $txt .= "  -- $key\n";
    if (exists $warnings{$key}) {
      my @list = @{$warnings{$key}};
      $txt .= &format_list("    - WARNINGS:", "      ", @list);
    }
    if (exists $notes{$key}) {
      my @list = @{$notes{$key}};
      $txt .= &format_list("    - NOTES:", "      ", @list);
    }
  }

  $txt = "\n$txt"
    if (! MMisc::is_blank($txt));

  return($txt);
}

##########

sub check_submission {
  my ($sf) = @_;

  vprint(1, "Checking Submission");

  my $err = MMisc::check_file_r($sf);
  return($err) if (! MMisc::is_blank($err));

  vprint(2, "Checking file extension");
  # due to the use of . as a valid component of file names
  # we can not use MMisc::split_dir_file_ext directly
  my $f = $sf;
  return("File must end in \'$kwslist_ext\'")
    if (! ($f =~ s%$kwslist_ext$%%i));
  $f =~ s%^.+/%%; # erase the directory part of the file

  vprint(2, "Checking EXPID");
  my ($lerr, $ltag, $lteam, $lcorpus, $lpart, $lscase, $ltask, $ltrncond, $lsysid, $lversion) = &check_name($f);
  return($lerr) if (! MMisc::is_blank($lerr));

  vprint(2, "Confirming having matching ECF & TLIST");
  return("Can not validate; no usable ECF & TLIST files with <CORPUSID> = $lcorpus | <PARTITION> = $lpart in \'dbDir\'")
    if (! MMisc::safe_exists(\%ecfs, $lcorpus, $lpart));

  vprint(2, "Running Validation tool");
  my $n_ecf = $ecfs{$lcorpus}{$lpart};
  my $n_tlist = $tlists{$lcorpus}{$lpart};
  my $n_rttm = (MMisc::safe_exists(\%rttms, $lcorpus, $lpart)) ? $rttms{$lcorpus}{$lpart} : "";

  $err = &run_ValidateKWSList($f, $sf, $n_ecf, $n_tlist, $n_rttm);
  return($err);
}

##########

sub cmp_exp {
  my ($t, $v, @e) = @_;

  return("$t ($v) does not compare to expected value (" . join(" ", @e) ."). ")
    if (! grep(m%^$v$%, @e));

  return("");
}

##

sub check_name {
  my ($name) = @_;

  my $et = "\'EXP-ID\' not of the form \'${kwsyear}_<TEAM>_<CORPUS>_<PARTITION>_<SCASE>_<TASK>_<TRNCOND>_<SYSID>_<VERSION>\' : ";
  
  my ($ltag, $lteam, $lcorpus, $lpart, $lscase, $ltask, $ltrncond, $lsysid, $lversion,
      @left) = split(m%\_%, $name);
  
  return($et . " leftover entries: " . join(" ", @left) . ". ", "")
    if (scalar @left > 0);
  
  return($et ." missing parameters. ", "")
    if (MMisc::any_blank($ltag, $lteam, $lcorpus, $lpart, $lscase, $ltask, $ltrncond, $lsysid, $lversion));
  
  my $err = "";
  
  $err .= &cmp_exp($kwsyear, $ltag, @expid_tag);

  $err .= " <TEAM> ($lteam) is different from required <TEAM> ($eteam). "
    if ((defined $eteam) && ($eteam ne $lteam));
  
  $err .= &cmp_exp("<PARTITION>",  $lpart, @expid_partition);
  $err .= &cmp_exp("<SCASE>", $lscase, @expid_scase);
  $err .= &cmp_exp("<TASK>", $ltask, @expid_task);
  $err .= &cmp_exp("<TRNCOND>", $ltrncond, @expid_trncond);
  
  my $b = substr($lsysid, 0, 2);
  $err .= "<SYSID> ($lsysid) does not start by expected value (" 
    . join(" ", @expid_sysid_beg) . "). "
    if (! grep(m%^$b$%, @expid_sysid_beg));
  
  $err .= "<VERSION> ($lversion) not of the expected form: integer value starting at 1). "
    if ( ($lversion !~ m%^\d+$%) || ($lversion =~ m%^0%) || ($lversion > 199) );
  # More than 199 submissions would make anybody suspicious ;)
  
  return($et . $err, "")
    if (! MMisc::is_blank($err));
  
  vprint(3, "$ltag | <TEAM> = $lteam | <CORPUS> = $lcorpus | <PARTITION> = $lpart | <SCASE> = $lscase | <TASK> = $ltask | <TRNCOND> = $ltrncond | <SYSID> = $lsysid | <VERSION> = $lversion");
  
  return("", $ltag, $lteam, $lcorpus, $lpart, $lscase, $ltask, $ltrncond, $lsysid, $lversion);
}

####

sub run_ValidateKWSList {
  my ($exp, $file, $ecf, $term, $rttm) = @_;

  vprint(3, "Creating the validation directory structure");

  my $od = "$outdir/$exp";
  return("Problem creating output dir ($od)")
    if (! MMisc::make_wdir($od));
  vprint(4, "Output dir: $od");
  
  my $of = "$od/$exp$kwslist_ext";

  my @cmd = ();
  push @cmd, '-e', $ecf;
  push @cmd, '-t', $term;
  push @cmd, '-s', $file;
  if ($scoringReady) {
    push(@cmd, '-r', $rttm) if (! MMisc::is_blank($rttm));
    push @cmd, '-m', $od;
  } else {
    push @cmd, '-o', $of;
  }

  my $lf = "$od/ValidateKWSList_run.log";
  vprint(4, "Running tool ($ValidateKWSList), log: $lf");
  my ($err) = &run_tool($lf, $ValidateKWSList, @cmd);

  return($err) if (! MMisc::is_blank($err));

  return("");
}

#####

sub run_tool {
  my ($lf, $tool, @cmds) = @_;

  $lf = MMisc::get_tmpfilename() if (MMisc::is_blank($lf));

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    MMisc::write_syscall_smart_logfile($lf, $tool, @cmds); 
  if ((! $ok) || ($rc != 0)) {
    my $lfc = MMisc::slurp_file($of);
    return("There was a problem running the tool ($tool) command\n  Run log (located at: $of) content: $lfc\n\n");
  }

  return("", $ok, $otxt, $so, $se, $rc, $of);
}

########################################

sub split_corpus_partition {
  my ($f, $e) = @_;
  $f =~ s%$e$%%i;
  my (@rest) = split(m%\_%, $f);
  MMisc::error_quit("Could not split ($f) in <CORPUSID>_<PARTITION>")
    if (scalar @rest != 2);
  return("", @rest);
}

#####

sub prune_list {
  my $dir = shift @_;
  my $ext = shift @_;
  my $robj = shift @_;

  my @list = grep(m%$ext$%i, @_);
  my %rest = MMisc::array1d_to_ordering_hash(\@_);
  for (my $i = 0; $i < scalar @list; $i++) {
    my $file = $list[$i];
    my ($err, $cid, $pid) = split_corpus_partition($file, $ext);
    MMisc::error_quit($err) if (! MMisc::is_blank($err));
    my $here = "$dir/$file";
    MMisc::warn_print("An \'$ext\' file already exist for <CORPUSID> = $cid | <PARTITION> = $pid (" . $$robj{$cid}{$pid} . "), being replaced by: $here")
      if (MMisc::safe_exists($robj, $cid, $pid));
    $$robj{$cid}{$pid} = $here;
    delete $rest{$file};
  }

  return(sort {$rest{$a} <=> $rest{$b}} (keys %rest));
}

##

sub obtain_ecf_tlist {
  my ($dir, $recf, $rtlist, $rrttm) = @_;

  my @files = MMisc::get_files_list($dir);

  @files = &prune_list($dir, $tlist_ext, $rtlist, @files);
  @files = &prune_list($dir, $rttm_ext, $rrttm, @files);
  @files = &prune_list($dir, $ecf_ext, $recf, @files);
}

#####

sub check_ecf_tlist_pairs {
  my ($recf, $rtlist, $rrttm) = @_;

  vprint(1, "Checking found ECF & TLIST");
  my @tmp1 = keys %$recf;
  push @tmp1, keys %$rtlist;
  foreach my $k1 (sort (MMisc::make_array_of_unique_values(\@tmp1))) {
    MMisc::error_quit("Can not find any ECF with <CORPUSID>: $k1")
      if (! exists $$recf{$k1});
    MMisc::error_quit("Can not find any Termlist with <CORPUSID>: $k1")
      if (! exists $$rtlist{$k1});
    my @tmp2 = keys %{$$recf{$k1}};
    push @tmp2, keys %{$$rtlist{$k1}};
    foreach my $k2 (sort (MMisc::make_array_of_unique_values(\@tmp2))) {
      MMisc::error_quit("Can not find any ECF with <PARTITION>: $k2")
        if (! exists $$recf{$k1}{$k2});
      MMisc::error_quit("Can not find any Termlist with <PARTITION>: $k2")
        if (! exists $$rtlist{$k1}{$k2});
      my @a = ();
      push (@a, $rttm_ext) if (MMisc::safe_exists($rrttm, $k1, $k2));
      my $tmp = (scalar @a > 0) ? " | \'" . join("\' & \'", @a) . "\' found" : "";
      vprint(2, "Have <CORPUSID> = $k1 | <PARTITION> = $k2$tmp");
    }
  }
}

##########

sub vprint {
  return if (! $verb);
  my $s = "********************";
  print substr($s, 0, shift @_), " ", join("", @_), "\n";
}

############################################################

sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

############################################################

sub set_usage {
  my $tmp=<<EOF
$versionid

Usage: $0 [--help | --version] --Specfile perlEvalfile --dbDir dir [--dbDir dir [...]] [--kwslistValidator tool] [--Verbose] [--outdir dir] [--scoringReady] [--quit_if_non_scorable] EXPID$kwslist_ext

Will confirm that a submission file conforms to the BABEL 'Submission Instructions'.

The program needs a 'dbDir' to load some of its eval specific definitions; this directory must contain pairs of <CORPUSID>_<PARTITION> \"$ecf_ext\" and \"$tlist_ext\" files that match the component of the EXPID.

 Where:
  --help          Print this usage information and exit
  --version       Print version number and exit
  --Specfile      Specify the \'perlEvalfile\' that contains definitions specific to the evaluation run
  --dbDir         Directory where the sidecar files are located. Multiple can be specified by separating them using a colon (\':\') or using the option multiple time
  --kwslistValidator  Location of the \'ValidateKWSList\' tool (default: $ValidateKWSList)
  --Verbose       Explain step by step what is being checked
  --outdir        Output directory where validation is performed (if not provided, default is to use a temporary directory)
  --scoringReady  When using this mode, a copy of the \"$ecf_ext\", \"$tlist_ext\" and \"$rttm_ext\" (if present) files will be created & memdump-ed in \'--outdir\' for scoring
  --quit_if_non_scorable  If for any reason, any submission is non scorable, quit without continuing the check process, instead of adding information to a report printed at the end

EOF
    ;

    return $tmp;
}