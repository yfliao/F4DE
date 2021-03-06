#!/bin/sh
#! -*-perl-*-
eval 'exec env PERL_PERTURB_KEYS=0 PERL_HASH_SEED=0 perl -x -S $0 ${1+"$@"}'
    if 0;

# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#
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
# Check we have every module (perl wise)

## First insure that we add the proper values to @INC
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

  push @f4bv, ("$f4d/../../lib", "$f4d/../../../common/lib");
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
my $partofthistool = "It should have been part of this tools' files.";
my $warn_msg = "";

# Part of this tool
foreach my $pn ("MMisc", "KWSEval_SCHelper", "KWSList") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}
my $versionkey = MMisc::slurp_file(dirname(abs_path($0)) . "/../../../.f4de_version");
my $versionid = "KWSEval Submission Checker ($versionkey)";

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
my $tlist_ext = '.kwlist.xml';
my $tlist_ext_rgx = '\.kwlist\d*\.xml';

my $rttm_ext = ".rttm";

my $kwslist_ext = '\.kwslist\d*\.xml';
my $ctm_ext = ".ctm";
my $stm_ext = ".stm";

my $ValidateKWSList = "$f4d/../ValidateKWSList/ValidateKWSList.pl";

my $ValidateTM = "$f4d/../ValidateTM/ValidateTM.pl";

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
my $aMT = 0;
my $descFile = "";
my $descDumpFile = "";
my $requireDesc = 0;
my $bypassxmllint = 0;
my $forceSpecfile = undef;
my $mode = undef;

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz #
# Used: A  D F    K   O   ST V X     d   h  k   o qrst v x z #

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
   'TmValidator=s' => \$ValidateTM,
   'scoringReady'   => \$scoringReady,
   'AllowMissingTerms' => \$aMT,
   'DescFile=s' => \$descFile,
   'xDescDump=s' => \$descDumpFile,
   'requireDesc' => \$requireDesc,
   'XmllintBypass' => \$bypassxmllint,
   'ForceSpecfile:s' => \$forceSpecfile,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");


MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});

MMisc::error_quit("No arguments left on command line\n\n$usage\n")
  if (scalar @ARGV == 0);

MMisc::error_quit("Cannot run system description check with multiple submissions")
  if (scalar @ARGV > 1 && ! MMisc::is_blank($descFile));

MMisc::error_quit("System description required but is not provided")
  if ($requireDesc && MMisc::is_blank($descFile));

MMisc::error_quit("Can't dump system description data if it is not provided")
  if (MMisc::is_blank($descFile) && ! MMisc::is_blank($descDumpFile));

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
$err = MMisc::check_file_x($ValidateTM);
MMisc::error_quit("Problem with ValidateTM ($ValidateTM): $err")
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
my %stms = ();
my @babellr = ();
for (my $i = 0; $i < scalar @dbDir; $i++) {
  $err = MMisc::check_dir_r($dbDir[$i]);
  MMisc::error_quit("Problem with \'dbDir\' (" . $dbDir[$i] . ") : $err")
    if (! MMisc::is_blank($err));
  KWSEval_SCHelper::obtain_ecf_tlist
    ($dbDir[$i], 
     $ecf_ext, \%ecfs, 
     $tlist_ext_rgx, \%tlists, 
     $rttm_ext, \%rttms, 
     \%stms);
  #KWSEval_SCHelper::obtain_lrlist($dbDir[$i], \@babellr) unless MMisc::is_blank($descFile);
}
MMisc::error_quit("Did not find any ECF or TLIST files; will not be able to continue")
  if ((scalar (keys %ecfs) == 0) || (scalar (keys %tlists) == 0));
KWSEval_SCHelper::check_ecf_tlist_pairs($verb, \%ecfs, \%tlists, $rttm_ext, \%rttms, $stm_ext, \%stms);

########################################

if (defined $forceSpecfile) {
  if (! MMisc::is_blank($forceSpecfile)) {
    $specfile = $forceSpecfile;
    my $err = MMisc::check_file_r($specfile);
    MMisc::error_quit("Problem with \'ForceSpecfile\' ($specfile) : $err")
      if (! MMisc::is_blank($err));
  }
} else {
# Find the preferred specfile
  $specfile = KWSEval_SCHelper::selectSpecfile($specfile, @dbDir);
}
my $kwsyear = KWSEval_SCHelper::loadSpecfile($specfile, $ctm_ext, $kwslist_ext);

my %AuthorizedSet = KWSEval_SCHelper::get_AuthorizedSet();

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

  my ($err) = &check_submission($sf, $descFile, $descDumpFile);
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
  &valok($fname, "[ERROR] ** Please refer to the \'Submission Instructions\', in the Appendices of the \'KWS Evaluation Plan\' for more information");

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
  my ($sf, $descf, $dumpf) = @_;

  vprint(1, "Checking Submission");

  my $err = MMisc::check_file_r($sf);
  return($err) if (! MMisc::is_blank($err));

  vprint(2, "Checking file extension");
  # due to the use of . as a valid component of file names
  # we can not use MMisc::split_dir_file_ext directly
  my $f = $sf;

  # Remove the file ending (and extract it value for 'mode' selector)
  if ($f =~ s%($kwslist_ext)$%%i) {
    $mode = $1;
  } elsif ($f =~ s%$ctm_ext$%%i) {
    $mode = $ctm_ext;
  } else {
    return("File must end in either \'$kwslist_ext\' or \'$ctm_ext\' to be usable")
      if (! defined $mode);
  }
  $f =~ s%^.+/%%; # erase the directory part of the file

  vprint(2, "Checking EXPID");
  my ($lerr, $ltag, $lteam, $lcorpus, $lpart, $lscase, $ltask, $ltrncond, $lsysid, $lversion, $lp, $lr, $laud) = KWSEval_SCHelper::check_name($kwsyear, $eteam, $f, $mode, $verb);
  return($lerr) if (! MMisc::is_blank($lerr));
  
  return("No Rule set for <PARTITION>=$lpart <SCASE>=$lscase")
    if (! MMisc::safe_exists(\%AuthorizedSet, $lpart, $lscase));
  return("The <PARTITION>=$lpart <SCASE>=$lscase combination is not authorized")
    if ($AuthorizedSet{$lpart}{$lscase} == 0);
  
  if ($requireDesc) {
      my ($rerr, $resources) = KWSEval_SCHelper::get_recog_resources(@dbDir);
      return($rerr) unless MMisc::is_blank($rerr);
      my ($derr, $data) = KWSEval_SCHelper::check_system_description($descf, $resources);
      return($derr) unless MMisc::is_blank($derr);

      unless (MMisc::is_blank($dumpf)) {
          open DUMP, ">$dumpf.dump";
          foreach my $type (keys %$data) {
              foreach my $d (keys %{ $data->{$type} }) {
                  my $val = join('+', (ref $data->{$type}{$d} eq "ARRAY" ? @{ $data->{$type}{$d} } : $data->{$type}{$d}));
                  print DUMP "$val\tVal\t$type|$d\n";                  
              }
          }
          close DUMP;
      }
  }

  if ($mode =~ m%$kwslist_ext%) {
    return(&kwslist_validation($f, $sf, $lcorpus, $lpart));
  } elsif ($mode eq $ctm_ext) {
    return(&ctm_validation($f, $sf, $lcorpus, $lpart));
  } else {
    MMisc::error_quit("Internal error - unknown mode: $mode");
  }
}

##

sub kwslist_validation {
  my ($f, $sf, $lcorpus, $lpart) = @_;

  vprint(2, "Confirming having matching ECF & TLIST");
  return("Can not validate; no usable ECF & TLIST files with <CORPUSID> = $lcorpus | <PARTITION> = $lpart in \'dbDir\'. Found ".join(", ",sort keys %ecfs))
    if (! MMisc::safe_exists(\%ecfs, $lcorpus, $lpart));

  vprint(2, "Running Validation tool");
  my $n_ecf = $ecfs{$lcorpus}{$lpart};
#  my $n_tlist = $tlists{$lcorpus}{$lpart};
  my $n_rttm = (MMisc::safe_exists(\%rttms, $lcorpus, $lpart)) ? $rttms{$lcorpus}{$lpart} : "";

  my ($err, $n_tlist) = KWSEval_SCHelper::check_kwslist_kwlist($sf, $bypassxmllint, @dbDir);
  return($err) if (! MMisc::is_blank($err));

  $err = &run_ValidateKWSList($f, $sf, $n_ecf, $n_tlist, $n_rttm);
  return($err);
}

##

sub ctm_validation {
  my ($f, $sf, $lcorpus, $lpart) = @_;

  vprint(2, "Confirming having matching ECF");
  return("Can not validate; no usable ECF file with <CORPUSID> = $lcorpus | <PARTITION> = $lpart in \'dbDir\'")
    if (! MMisc::safe_exists(\%ecfs, $lcorpus, $lpart));

  vprint(2, "Running Validation tool");
  my $n_ecf = $ecfs{$lcorpus}{$lpart};
  my $n_stm = (MMisc::safe_exists(\%stms, $lcorpus, $lpart)) ? $stms{$lcorpus}{$lpart} : "";

  $err = &run_ValidateTM($f, $sf, $n_ecf, $n_stm);
  return($err);
}

##########

sub run_ValidateTM {
  my ($exp, $ctm, $ecf, $stm) = @_;

  vprint(3, "Creating the validation directory structure");

  my $od = "$outdir/$exp";
  return("Problem creating output dir ($od)")
    if (! MMisc::make_wdir($od));
  vprint(4, "Output dir: $od");
  my $of = "$od/$exp$ctm_ext";

  my @cmd = ();
  push @cmd, '-E', $ecf;
  push @cmd, '-C', $ctm;
  if ($scoringReady) {
    push(@cmd, '-S', $stm) if (! MMisc::is_blank($stm));
  } # else {
#    push @cmd, '-o', $of;
#  }

  my $lf = "$od/ValidateTM_run.log";
  vprint(4, "Running tool ($ValidateTM), log: $lf");
  my ($err) = &run_tool($lf, $ValidateTM, @cmd);
  return($err) if (! MMisc::is_blank($err));

  # ok, copy CTM to $od
  $err = MMisc::filecopy($ctm, $of);
  return($err) if (! MMisc::is_blank($err));

  return("");
}

#####

sub run_ValidateKWSList {
  my ($exp, $file, $ecf, $term, $rttm) = @_;

  vprint(3, "Creating the validation directory structure");

  my $od = "$outdir/$exp";
  return("Problem creating output dir ($od)")
    if (! MMisc::make_wdir($od));
  vprint(4, "Output dir: $od");
  my $of = "$od/$exp$mode";

  my @cmd = ();
  push @cmd, '-e', $ecf;
  push @cmd, '-t', $term;
  push @cmd, '-s', $file;
  push(@cmd, '-A') if ($aMT);
  push(@cmd, '-X') if ($bypassxmllint);
  if ($scoringReady) {
    push(@cmd, '-r', $rttm) if (! MMisc::is_blank($rttm));
#    push @cmd, '-m', $od;
  } # else {
#    push @cmd, '-o', $of;
#  }

  my $lf = "$od/ValidateKWSList_run.log";
  vprint(4, "Running tool ($ValidateKWSList), log: $lf");
  my ($err) = &run_tool($lf, $ValidateKWSList, @cmd);
  return($err) if (! MMisc::is_blank($err));

  # ok, copy KWSlist to $od
  $err = MMisc::filecopy($file, $of);
  return($err) if (! MMisc::is_blank($err));

  return("");
}

#####

sub run_tool {
  my ($lf, $tool, @cmds) = @_;

  $lf = MMisc::get_tmpfile() if (MMisc::is_blank($lf));

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    MMisc::write_syscall_smart_logfile($lf, $tool, @cmds); 
  if ((! $ok) || ($rc != 0)) {
    my $lfc = MMisc::slurp_file($of);
    return("There was a problem running the tool ($tool) command\n  Run log (located at: $of) content: $lfc\n\n");
  }

  return("", $ok, $otxt, $so, $se, $rc, $of);
}

########################################

sub vprint {
  return if (! $verb);
  my $s = "********************";
  print substr($s, 0, shift @_), " ", join("", @_), "\n";
}

############################################################

sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

############################################################
   # 'DescFile=s' => \$descFile,
   # 'xDescDump=s' => \$descDumpFile,
sub set_usage {
  my $tmp=<<EOF
$versionid

Usage: $0 [--help | --version] --Specfile perlEvalfile [--ForceSpecfile [perlEvalfile]] --dbDir dir [--dbDir dir [...]] [--kwslistValidator tool [--AllowMissingTerms] [--XmllintBypass]] [--TmValidator tool] [--DescFile sysDescfile [--xDescDump sysDescDumpfile]] [--requireDesc] [--Verbose] [--outdir dir] [--scoringReady] [--quit_if_non_scorable] EXPID.extension

Will confirm that a submission file conforms to the BABEL 'Submission Instructions'.

The program needs a 'dbDir' to load some of its eval specific definitions.

".extension" is one of: $kwslist_ext $ctm_ext
  For \'$kwslist_ext\' files, this directory must contain pairs of <CORPUSID>_<PARTITION> \"$ecf_ext\" and \"$tlist_ext\" files that match the component of the EXPID.
  For \'$ctm_ext\' files, only the \'$ecf_ext\' file is required.

 Where:
  --help          Print this usage information and exit
  --version       Print version number and exit
  --Specfile      Configuration file containing EXPID definition (note: if a specfile with the same filename is found in a dbDir, this specialized version will be used unless --ForceSpecfile is used)
  --ForceSpecfile  Force the use of the default specfile if no value is provided, or the selected file is provided (overriding the dbDir lookup)
  --dbDir         Directory where the sidecar files are located. Multiple can be specified by separating them using a colon (\':\') or using the option multiple time
  --kwslistValidator  Location of the \'ValidateKWSList\' tool (default: $ValidateKWSList) for validating \'$kwslist_ext\' files
  --AllowMissingTerms  Authorize TERMs defined in KWList file but not in the KWSlist file
  --XmllintBypass      Bypass xmllint check of the KWSList XML file (this will reduce the memory footprint when loading the file, but requires that the file be formatted in a way similar to how \'xmllint --format\' would)
  --TmValidator  Location of the \'ValidateTM\' tool (default: $ValidateTM) for validating \'$ctm_ext\' files
  --DescFile      System description file to be checked with the submission
  --xDescDump     File to dump the system description data (.dump will be appended to the filename)
  --requireDesc   Require system description file
  --Verbose       Explain step by step what is being checked
  --outdir        Output directory where validation is performed (if not provided, default is to use a temporary directory)
  --scoringReady  When using this mode, a copy of the input file for validation will be copied in \'--outdir\' for scoring
  --quit_if_non_scorable  If for any reason, any submission is non scorable, quit without continuing the check process, instead of adding information to a report printed at the end

EOF
   ;

    return $tmp;
}
