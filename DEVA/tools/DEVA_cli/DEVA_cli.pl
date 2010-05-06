#!/usr/bin/env perl
# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs

# DEVA Command Line Interface
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "DEVA_cli" is an experimental system.
# NIST assumes no responsibility whatsoever for its use by any party.
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

my $versionid = "DEVA Command Line Interfce Version: $version";

##########
# Check we have every module (perl wise)

my ($f4b, @f4bv);
BEGIN {
  $f4b = "F4DE_BASE";
  push @f4bv, (exists $ENV{$f4b}) 
    ? ($ENV{$f4b} . "/lib") 
      : ("../../../common/lib");
}
use lib (@f4bv);

sub eo2pe {
  my $oe = join(" ", @_);
  return( ($oe !~ m%^Can\'t\s+locate%) ? "\n----- Original Error:\n $oe\n-----" : "");
}

## Then try to load everything
my $have_everything = 1;
my $partofthistool = "It should have been part of this tools' files. Please check your $f4b environment variable.";
my $warn_msg = "";
sub _warn_add { $warn_msg .= "[Warning] " . join(" ", @_) ."\n"; }

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

my $defusedmetric = "MetricNormLinearCostFunct";
my $mancmd = "perldoc -F $0";
my $usage = &set_usage();

my $outdir = "";
my $filtercmdfile = "";

my $doCfg = 1;
my $createDBs = 1;
my $filter = 1;
my $score = 1;

my $wrefCFfile = "";
my $wsysCFfile = "";
my $wmdCFfile  = "";

my $refcsv = "";
my $syscsv = "";

my $wrefDBfile = "";
my $wsysDBfile = "";
my $wmdDBfile  = "";
my @addResDBfiles = ();
my $resDBbypass = 0;

my $usedmetric = "";
my @usedmetparams = ();
my @trialsparams = ();
my $listparams = 0;

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used: A CD F     LM    RST  W   a c  fgh   lm o  rst vwx    #

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'man',
   'outdir=s' => \$outdir,
   'refcsv=s' => \$refcsv,
   'syscsv=s' => \$syscsv,
   'configSkip' => sub { $doCfg = 0},
   'CreateDBSkip' => sub { $createDBs = 0},
   'filterSkip' => sub { $filter = 0},
   'FilterCMDfile=s' => \$filtercmdfile,
   'DETScoreSkip' => sub { $score = 0},
   'RefDBfile=s' => \$wrefDBfile,
   'SysDBfile=s' => \$wsysDBfile,
   'MetadataDBfile=s' => \$wmdDBfile,
   'addResDBfiles=s' => \@addResDBfiles,
   'AllowResDBfileBypass' => \$resDBbypass,
   'usedMetric=s' => \$usedmetric,
   'UsedMetricParams=s' => \@usedmetparams,
   'TrialsParams=s' => \@trialsparams,
   'listParams' => \$listparams,
   'wREFcfg=s'  => \$wrefCFfile,
   'WSYScfg=s'  => \$wsysCFfile,
   'xMDcfg=s'   => \$wmdCFfile,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});
if ($opt{'man'}) {
  my ($r, $o, $e) = MMisc::do_system_call($mancmd);
  MMisc::error_quit("Could not run \'$mancmd\'") if ($r);
  MMisc::ok_quit($o);
}

my ($sqlite_cfg_helper, $sqlite_tables_creator, $sqlite_load_csv, 
  $deva_filter, $deva_sci) =
  ( "SQLite_cfg_helper", "SQLite_tables_creator", "SQLite_load_csv", 
    "DEVA_filter", "DEVA_sci");

if ($listparams) {
  MMisc::error_quit("Specified \'metric\' does not seem to be using a valid name ($usedmetric), should start with \"Metric\"")
    if ((! MMisc::is_blank($usedmetric)) && (! ($usedmetric =~ m%^metric%i)));

  my $tool = &path_tool($deva_sci, "../../../DEVA/tools/DEVA_sci");

  my $cmdp = "-l";
  $cmdp .= " -m $usedmetric" if (! MMisc::is_blank($usedmetric));

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    &run_tool("", $tool, $cmdp);

  MMisc::ok_quit($so);
}

my @csvlist = @ARGV;

my $err = MMisc::check_dir_w($outdir);
MMisc::error_quit("Problem with output directory ($outdir): $err\n$usage\n")
  if (! MMisc::is_blank($err));

my $logdir = "$outdir/_logs";
MMisc::error_quit("Could not create log dir ($logdir)")
  if (! MMisc::make_dir($logdir));

my $mdDBbase = "$outdir/metadataDB";
my $mdDBcfg  = (MMisc::is_blank($wmdCFfile)) ? "$mdDBbase.cfg" : $wmdCFfile;
my $mdDBfile = (MMisc::is_blank($wmdDBfile)) ? "$mdDBbase.db" : $wmdDBfile;
my $mdDBlogb = "$logdir/metadataDB";

my $refDBbase = "$outdir/referenceDB";
my $refDBcfg  = (MMisc::is_blank($wrefCFfile)) ? "$refDBbase.cfg" : $wrefCFfile;
my $refDBfile = (MMisc::is_blank($wrefDBfile)) ? "$refDBbase.db" : $wrefDBfile;
my $refDBlogb = "$logdir/referenceDB";

my $sysDBbase = "$outdir/systemDB";
my $sysDBcfg  = (MMisc::is_blank($wsysCFfile)) ? "$sysDBbase.cfg" : $wsysCFfile;
my $sysDBfile = (MMisc::is_blank($wsysDBfile)) ? "$sysDBbase.db" : $wsysDBfile;
my $sysDBlogb = "$logdir/systemDB";

my $resDBbase = "$outdir/filterDB";
my $resDBfile = "$resDBbase.db";

my $finalDBbase = "$outdir/scoreDB";
my $finalDBfile = "$finalDBbase.db";


if ($doCfg) {
  print "***** Generating config files\n";
  my $done = 0;
#  MMisc::warn_print("No CVS file list given, no metadataDB file will be generated")
#    if (scalar @csvlist == 0);

  if (! MMisc::is_blank($refcsv)) {
    print "** REF\n";
    my $tmp = &do_cfgfile
      ($refDBcfg, "${refDBlogb}_cfggen.log", "-T Reference -p TrialID", $refcsv);
    &check_isin($tmp, '^newtable:\s+Reference$', '^column\*:\s+TrialID;', '^column:\s+Targ;TEXT$');
    $done++;
  }
  
  if (! MMisc::is_blank($syscsv)) {
    print "** SYS\n";
    my $tmp = &do_cfgfile
      ($sysDBcfg, "${sysDBlogb}_cfggen.log", "-T System -p TrialID", $syscsv);
    &check_isin($tmp, '^newtable: System$', '^column\*:\s+TrialID;', '^column:\s+Decision;TEXT$', '^column:\s+Score;');
    $done++;
  }
  
  if (scalar @csvlist > 0) {
    print "** Metadata\n";
    my $tmp = &do_cfgfile
      ($mdDBcfg, "${mdDBlogb}_cfggen.log", 
       "-c ${mdDBbase}_columninfo.txt -t ${mdDBbase}_tableinfo.txt", 
       @csvlist);
    $done++;
  }

  print "-> $done config file generated\n";
}

if ($createDBs) {
  print "***** Creating initial DataBases (if not already present)\n";
  my $done = 0;
  
  if (MMisc::does_file_exists($refDBcfg)) {
    print "** REF\n";
    &db_create($refDBcfg, $refDBfile, "${refDBlogb}_DBgen.log");
    $done++;
  }
  
  if (MMisc::does_file_exists($sysDBcfg)) {
    print "** SYS\n";
    &db_create($sysDBcfg, $sysDBfile, "${sysDBlogb}_DBgen.log");
    $done++;
  }
  
  if (MMisc::does_file_exists($mdDBcfg)) {
    print "** Metadata\n";
    &db_create($mdDBcfg, $mdDBfile, "${mdDBlogb}_DBgen.log");
    $done++;
  }

  print "-> $done DB file generated\n";
}

if ($filter) {
  print "***** Running Filter\n";
  
  MMisc::error_quit("No such \'FilterCMDfile\' ($filtercmdfile)")
    if ((MMisc::is_blank($filtercmdfile)) || (! MMisc::is_file_r($filtercmdfile)));
  
  &check_file_r($refDBfile);
  &check_file_r($sysDBfile);
  $mdDBfile = &check_file_r($mdDBfile, 1);
  
  &run_filter("$logdir/filterTool.log", $refDBfile, $sysDBfile, $mdDBfile, $filtercmdfile, $resDBfile);
}

if ($score) {
  print "***** Scoring\n";

  &check_file_r($refDBfile);
  &check_file_r($sysDBfile);
  $resDBfile = &check_file_r($resDBfile, $resDBbypass);
  for (my $i = 0; $i < scalar @addResDBfiles; $i++) {
    &check_file_r($addResDBfiles[$i]);
  }

  &run_scorer("$logdir/TrialScore.log", $refDBfile, $sysDBfile, $finalDBfile, $resDBfile, @addResDBfiles);
}

MMisc::ok_quit("Done");

########################################

sub check_fn4 {
  my ($fn, $in) = @_;

  my ($err, $d, $f, $e) = MMisc::split_dir_file_ext($fn);
  MMisc::error_quit("Problem checking file name ($fn): $err")
    if (! MMisc::is_blank($err));
  
  MMisc::error_quit("File ($fn) does not share expected base ($in), is ($f)")
    if ($in ne $f);
}

#####

sub do_cfgfile {
  my ($cfgfile, $log, $cmdadd, @csvfl) = @_;

  my $tool = &path_tool($sqlite_cfg_helper, "../../../common/tools/SQLite_tools");

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    &run_tool($log, $tool, $cmdadd, @csvfl);

  MMisc::error_quit("Problem writing config file ($cfgfile)")
    if (! MMisc::writeTo($cfgfile, "", 0, 0, $so));

  return($so);
}

##########

sub db_create {
  my ($cfgfile, $dbfile, $log) = @_;

  if (MMisc::does_file_exists($dbfile)) {
    print " -> DB file already exists, not overwriting it\n";
    return();
  }

  my $err = MMisc::check_file_r($cfgfile);
  MMisc::error_quit("Problem with config file ($cfgfile): $err")
    if (! MMisc::is_blank($err));

  my $tool = &path_tool($sqlite_tables_creator, "../../../common/tools/SQLite_tools");
  my $tool2 = (exists $ENV{$f4b}) ? "" : 
    &path_tool($sqlite_load_csv, "../../../common/tools/SQLite_tools");

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    &run_tool($log, $tool, 
              "-l" . (MMisc::is_blank($tool2) ? "" : " -L $tool2") 
              . " $dbfile $cfgfile");
}

##########

sub check_file_r {
  my ($file, $lenient) = @_;

  my $err = MMisc::check_file_r($file);
  if (! MMisc::is_blank($err)) {
    if ($lenient) {
      MMisc::warn_print("Issue with non mandatory file ($file): $err");
      return("");
    }
    MMisc::error_quit("Problem with file ($file): $err")
  }

  return($file);
}

#####

sub run_filter {
  my ($log, $refDBfile, $sysDBfile, $mdDBfile, $filtercmdfile, $resDBfile) = @_;

  my $tool = &path_tool($deva_filter, "../../../DEVA/tools/DEVA_filter");

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    &run_tool($log, $tool, "-r $refDBfile -s $sysDBfile" .
              ((MMisc::is_blank($mdDBfile)) ? "" : " -m $mdDBfile" ) .
              " -F $filtercmdfile $resDBfile");
}

##########

sub run_scorer {
  my ($log, $refDBfile, $sysDBfile, $finalDBfile, @xres) = @_;

  my $tool = &path_tool($deva_sci, "../../../DEVA/tools/DEVA_sci");

  my $cmdp = "-r $refDBfile -s $sysDBfile";
  for (my $i = 0; $i < scalar @xres; $i++) {
    $cmdp .= " -R " . $xres[$i];
  }
  $cmdp .= " -b ${finalDBbase}_DET";
  $cmdp .= " -m $usedmetric" if (! MMisc::is_blank($usedmetric));
  foreach my $mk (@usedmetparams) {
    $cmdp .= " -M $mk";
  }
  foreach my $mk (@trialsparams) {
    $cmdp .= " -T $mk";
  }
  $cmdp .= " $finalDBfile";
  my ($ok, $otxt, $so, $se, $rc, $of) = 
    &run_tool($log, $tool, $cmdp);
}

##########

sub check_isin {
  my ($txt, @entries) = @_;

  for (my $i = 0; $i < scalar @entries; $i++) {
    my $v = $entries[$i];
    MMisc::error_quit("Could not find expected entry [$v]")
      if (! ($txt =~ m%$v%m));
  }
}

#####

sub path_tool {
  my ($toolb, $relpath) = @_;
  my $tool = (exists $ENV{$f4b}) 
    ? MMisc::cmd_which($toolb) 
    : "$relpath/${toolb}.pl";
  &check_tool($tool, $toolb);
  return($tool);
}

#####

sub check_tool {
  my ($tool, $toolb) = @_;
  MMisc::error("No location found for tool ($toolb)")
    if (MMisc::is_blank($tool));
  my $err = MMisc::check_file_x($tool);
  MMisc::error_quit("Problem with tool ($tool): $err")
    if (! MMisc::is_blank($err));
}

#####

sub run_tool {
  my ($lf, $tool, @cmds) = @_;

  $lf = MMisc::get_tmpfilename() if (MMisc::is_blank($lf));

  my ($ok, $otxt, $so, $se, $rc, $of) = 
    MMisc::write_syscall_smart_logfile($lf, $tool, @cmds); 
  MMisc::error_quit("There was a problem running the tool ($tool) command, see: $of")
    if ((! $ok) || ($rc != 0));

  return($ok, $otxt, $so, $se, $rc, $of);
}

############################################################ Manual

=pod

=head1 NAME

DEVA_cli - DEVA Command Line Interface

=head1 SYNOPSIS

B<DEVA_cli> S<[ B<--help> | B<--man> | B<--version> ]>
  S<B<--outdir> I<dir>>
  S<[B<--configSkip>] [B<--CreateDBSkip>] [B<--filterSkip>] [B<--DETScoreSkip>]>
  S<[B<--refcsv> I<csvfile>] [B<--syscsv> I<csvfile>]>
  S<[B<--wREFcfg> I<file>] [B<--WSYScfg> I<file>] [B<--xMDcfg> I<file>]>
  S<[B<--RefDBfile> I<file>] [B<--SysDBfile> I<file>] [B<--MetadataDBfile> I<file>]>
  S<[B<--FilterCMDfile> I<SQLite_commands_file>]> 
  S<[B<--usedMetric> I<package>]>
  S<[B<--UsedMetricParameters> I<parameter=value> [B<--UsedMetricParameters> I<parameter=value> [...]]>
  S<[B<--TrialsParameters> I<parameter=value> [B<--TrialsParameters> I<parameter=value> [...]]]>
  S<[B<--listParameters>]>
  [I<csvfile> [I<csvfile> [I<...>]]
  
=head1 DESCRIPTION

B<DEVA_cli> is a wrapper script to start from a set of CSV files, generate its configuraion file, then its database, apply a select filter on the database to obtain DETCurve information.

The script will work with the following tools (lookup their help page for more details):

=over

=item B<SQLite_cfg_helper> 

=item B<SQLite_tables_creator>

=item B<DEVA_filter>

=item B<DEVA_sci>

=back

=head1 PREREQUISITES

B<DEVA_cli> relies on some external software and files.

=over

=item B<SOFTWARE> 

I<sqlite3> (S<http://www.sqlite.org/>) is required (at least version 3.6.12) to perform all the SQL work.

I<gnuplot> (S<http://www.gnuplot.info/>) is also required (at least version 4.2) to generate the DETCurve plots.

=item B<GLOBAL ENVIRONMENT VARIABLE>

Once you have installed the software, setting B<F4DE_BASE> to the installation location, and extending your B<PATH> to include B<$F4DE_BASE/bin> should be sufficient for the tools to find their components.

=back

=head1 OPTIONS

=over

=item B<--CreateDBSkip>

Skip the database and tables generation.

This step uses the files created in the configuration generation step and generate multiple SQLite databases containing the tables specified their respective configuration files.

Files created during this step would be S<outdir/referenceDB.sql>, S<outdir/systemDB.sql> and S<outdir/metadataDB.sql>

=item B<--configSkip>

Skip the generation of the configuration files required for the generation of the database tables.

This process read each CSV file (I<refcsv>, I<syscsv> and metadata I<csvfile(s)>), determine the tables name, columns names and types and write them in S<outdir/referenceDB.cfg>, S<outdir/systemDB.cfg> and S<outdir/metadataDB.cfg> files.

=item B<--DETScoreSkip>

Skip the Trial Scoring step (including DETCurve processing).

This step rely on the S<outdir/referenceDB.sql>, S<outdir/systemDB.sql> and S<<outdir/filterDB.sql> files to extract into S<outdir/scoreDB.sql> a I<ref> and I<sys> table that only contains the I<TrialID>s left post-filtering.
This step also generate a few files starting with S<outdir/scoreDB_DET> that are the results of the DETCurve generation process.

=item B<--FilterCMDfile> I<SQLite_commands_file>

Specify the location of the SQL commands file used to extract the list of I<TrialID> that will be inserted in <output/filterDB.sql>.

=item B<--filterSkip>

Skip step that uses the SQL I<SELECT>s commands specified in the B<--FilterCMDfile> step to create the S<outdir/filterDB.sql> database (which only contains S<TrialID> information).

=item B<--help>

Display the usage page for this program. Also display some default values and information.

=item B<--listParameters>

List Metric and Trial package authorized parameters

=item B<--MetadataDBfile> I<file>

Specify the location of the Metadata database file to use/generate.

=item B<--man>

Display this man page.

=item B<--outdir> I<dir>

Specify the directory in which all files relevant to this call to B<DEVA_cli> will be placed (or looked for).

=item B<--RefDBfile> I<file>

Specify the location of the Reference database file to use/generate.

=item B<--refcsv> I<csvfile>

Specify the location of the Reference CSV file (expected to contain a S<TrialID> and S<Targ> columns).

=item B<--SysDBfile> I<file>

Specify the location of the System database file to use/generate.

=item B<--syscsv> I<csvfile>

Specify the location of the System CSV file (expected to contain S<TrialID>, S<Score> and S<Decision> columns).

=item B<--TrialsParameters> I<parameter=value>

Specify the parameters given during the Trial creation process.

=item B<--UsedMetricParameters> I<parameter=value>

Specify the parameters given during the Metric creation process.

=item B<--usedMetric> I<package>

Specify the Metric package to use for scoring data (must be in your perl serch path -- or part of F4DE).

=item B<--version>

Display the B<DEVA_cli> version information.

=item B<--WSYScfg> I<file>

Specify the System configuration file

=item B<--wREFcfg> I<file>

Specify the Refefence configuration file

=item B<--xMDcfg> I<file>

Specify the metadata configuration file

=back

=head1 USAGE

=item B<DEVA_cli --outdir outdir --refcsv ref.csv --syscsv sys.csv md.csv --FilterCMDfile filter1.sql>

This will process the four steps expected of the command line interface:

=over

=item Step 1 (uses B<SQLite_cfg_helper>)

Will use I<ref.csv> as the Reference CSV file, I<sys.csv> as the System CSV file and I<md.csv> as the Metadata CSV file.
From those files, the first step will generate the database creation configuration files by loading each rows and columns in the CSV to determine their SQLite type, and determine if the column header name as to be adapted to avoid characters not recognized by SQLite. This process will create the I<outdir/referenceDB.cfg>, I<outdir/systemDB.cfg> and I<outdir/metadataDB.cfg> files.

=item Step 2 (uses B<SQLite_tables_creator>)

The next step will use those configuration files to create SQLite database files containing:

=over

=item

One table called I<Reference> (containing at least one primary key column called I<TrialID> and one column called I<Targ> with S<y> or S<n> content) for I<outdir/referenceDB.db> which content is loaded from I<refrence.csv>.

=item

One table called I<System> (containing at least on primary key column called I<TrialID> as well as one I<Score> column and one I<Decision> with S<y> or S<n> content) for I<outdir/systemDB.db> which content is loaded from I<system.csv>

=item

As many tables as metadata CSV files (here only one) are added to <outdir/metadataDB.db>.

=back

=item Step 3 (uses B<DEVA_filter>)

The next step will use the I<filter1.sql> SQL command lines file to apply the given filter. For this step I<outdir/referenceDB.db> is loaded as I<referenceDB> (and contains a table named I<Reference>. Also, I<outdir/systemDB.db> is loaded as I<systemDB> (and contain a table named I<System>. And I<outdir/metadataDB.db> is loaded as I<metadataDB> and contain the table list specified in I<outdir/metadataDB.cfg>.
The filter is expected to only return a list of I<TrialID>s that will added be to I<outdir/filterDB.db>'s I<resultsTable> table.

=item Step 4 (uses B<DEVA_sci>)

The final step will use I<outdir/referenceDB.db>, I<outdir/systemDB.db> and I<outdir/filterDB.db> to select only the I<TrialID>s that are both in the I<resultsTables> and I<Reference> tables to create in the I<outdir/scoreDB.db> SQLite database file a I<ref> table that only contain the reference information matching the given I<TrialID>s.
The same is made from I<resultsTables> and I<System> tables to add a I<sys> table.

I<Trials> are then generated so that if a given entry is both in I<ref> and I<sys> is is considered I<mapped>, if it is only in I<ref> it is an I<unmapped_ref> entry, and if it is only is <sys> it is an I<unmapped_sys> entry.
Those I<Trials> are used for I<DETCurve> work. Each file starting with I<outdir/scoreDB_DET> is one of those results.

=back

=head1 BUGS

Please send bug reports to <nist_f4de@nist.gov>

=head1 AUTHORS

Martial Michel <martial.michel@nist.gov>

=head1 COPYRIGHT 

This software was developed at the National Institute of Standards and Technology by employees of the Federal Government in the course of their official duties.  Pursuant to Title 17 Section 105 of the United States Code this software is not subject to copyright protection within the United States and is in the public domain. It is an experimental system.  NIST assumes no responsibility whatsoever for its use by any party.

THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE.

=cut

##########

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] --outdir dir [--configSkip] [--CreateDBSkip] [--filterSkip] [--DETScoreSkip] [--refcsv csvfile] [--syscsv csvfile] [--wREFcfg file] [--WSYScfg file] [--xMDcfg file] [--RefDBfile file] [--SysDBfile file] [--MetadataDBfile file] [--FilterCMDfile SQLite_commands_file] [--usedMetric package] [--UsedMetricParameters parameter=value [--UsedMetricParameters parameter=value [...]] [--TrialsParameters parameter=value [--TrialsParameters parameter=value [...]]] [--listParameters] [csvfile [csvfile [...]]

Wrapper for all steps involved in a DEVA scoring step
Arguments left on the command line are csvfile used to create the metadataDB

NOTE: will create _logs directory in outdir

Where:
  --help     This help message
  --version  Version information
  --outdir   Specify the directory where are all the steps are being processed
  --configSkip    Bypass csv config helper step
  --CreateDBSkip  Bypasss Databases creation step
  --filterSkip    Bypasss Filter tool step
  --DETScoreSkip  Bypass Scoring Interface step
  --wREFcfg    Specify the Refefence configuration file
  --WSYScfg    Specify the System configuration file
  --xMDcfg     Specify the metadata configuration file
  --refcsv     Specify the Reference csv file
  --syscsv     Specify the System csv file
  --RefDBfile  Specify the Reference SQLite database file
  --SysDBfile  Specify the System SQLite database file
  --MetadataDBfile  Specify the metadata SQLite database file
  --FilterCMDfile  Specify the SQLite command file
  --addResDBfiles  Additional filter results database files to give the scorer (will do an AND on the TrialIDs)
  --usedMetric    Package to load for metric uses (if none provided, default used: $defusedmetric)
  --UsedMetricParameters Metric Package parameters
  --TrialsParameters Trials Package parameters
  --listParameters   List Metric and Trial package authorized parameters

EOF
;

  return($tmp);
}

