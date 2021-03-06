#!/bin/sh
#! -*-perl-*-
eval 'exec env PERL_PERTURB_KEYS=0 PERL_HASH_SEED=0 perl -x -S $0 ${1+"$@"}'
    if 0;

# -*- mode: Perl; tab-width: 2; indent-tabs-mode: nil -*- # For Emacs
#
# $Id$
#
# InnerJoin_Select
#
# Author(s): Martial Michel
#
# This software was developed at the National Institute of Standards and Technology by
# employees and/or contractors of the Federal Government in the course of their official duties.
# Pursuant to Title 17 Section 105 of the United States Code this software is not subject to 
# copyright protection within the United States and is in the public domain.
#
# "InnerJoin_Select" is an experimental system.
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
foreach my $pn ("MMisc", "MtSQLite", "CSVHelper") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}
my $versionkey = MMisc::slurp_file(dirname(abs_path($0)) . "/../../../.f4de_version");
my $versionid = "Inner Join Select Tool ($versionkey)";

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

my $wrkdir = "";
my $rescsv = "";

my $tooln = "DEVA_cli";
my $tool = "$f4d/../DEVA_cli/$tooln.pl";

my @keys = 
  (
   'csvfile', # CSV file
   'innerjoin', # Inner Join Columns
   'usecolumn', # Use column
  ); # order is important
my ($col_csv, $col_ijc, $col_use)
  = @keys;

my %tables = ();
my $ctable = "default";
my @tord = ();

my $tmpv = "";

# Av  : ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz  #
# Used:                    T        c    hi        r tuvw     #

my $usage = &set_usage();
MMisc::error_quit($usage) if (scalar @ARGV == 0);

my %opt = ();
GetOptions
  (
   \%opt,
   'help',
   'version',
   'wrkdir=s' => \$wrkdir,
   'rescsv=s' => \$rescsv,
   'table=s' => sub { &set_ctable($_[1]); },
   'csvfile=s' => sub { &add_csv_to_table($_[1]); },
   'innerjoin=s' => sub { &add_innerjoin_to_table($_[1]); },
   'usecolumn=s' => sub { &add_usecolumn_to_table($_[1]); },
   'Tool=s' => \$tool,
  ) or MMisc::error_quit("Wrong option(s) on the command line, aborting\n\n$usage\n");
MMisc::ok_quit("\n$usage\n") if ($opt{'help'});
MMisc::ok_quit("$versionid\n") if ($opt{'version'});

MMisc::error_quit("No \'wrkdir\' provided ?")
  if (MMisc::is_blank($wrkdir));

MMisc::error_quit("No \'rescsv\' provided ?")
  if (MMisc::is_blank($rescsv));

my $err = MMisc::check_dir_w($wrkdir);
MMisc::error_quit("Problem with \'wrkdir\' ($wrkdir) : $err")
  if (! MMisc::is_blank($err));

my $err = MMisc::check_file_x($tool);
MMisc::error_quit("Problem with tool ($tool) : $err")
  if (! MMisc::is_blank($err));

&check_tables();
&check_csv_columns();
MMisc::error_quit("Sorry, currently can only work with two tables, here: " . scalar @tord)
  if (scalar @tord != 2);

my $step = 1;
my @csv_headers = ();
my $db = "";
&doit();

MMisc::ok_quit("Done");

####################

sub fix_entries {
  my ($h, $print, @v) = @_;

  my @tmp = MtSQLite::fix_entries(@v);

  for (my $i = 0; $i < scalar @v; $i++) {
    my $o = $v[$i];
    my $n = $tmp[$i];

    next if ($n eq $o);

    print " !! For \'$h\' value \'$o\' had to be adaptapted for SQLite use as \'$n\'\n"
      if ($print);
  }

  return(@tmp);
}

#####

sub set_ctable {
  my ($ct) = @_;

  ($ctable) = &fix_entries("Table", 1, $ct);

  MMisc::error_quit("Table name already used ($ctable)")
      if (MMisc::safe_exists(\%tables, $ctable));

#  print "Table: [$ctable]\n";
  push @tord, $ctable;
}

#####

sub add_csv_to_table {
  my ($csv) = @_;

  MMisc::error_quit("No table specified")
      if ($ctable eq "default");

  my $err = MMisc::check_file_r($csv);
  MMisc::error_quit("Problem with CSV file ($csv) : $err")
      if (! MMisc::is_blank($err));

  MMisc::error_quit("Table \'$ctable\' already has a CSV file set : " 
                    . $tables{$ctable}{$col_csv})
      if (MMisc::safe_exists(\%tables, $ctable, $col_csv));

  $tables{$ctable}{$col_csv} = $csv;
}

#####

sub add_innerjoin_to_table {
  my ($ijc) = @_;

  MMisc::error_quit("No table specified")
      if ($ctable eq "default");

  MMisc::error_quit("Table \'$ctable\' already has an Inner Join Column set : " 
                    . $tables{$ctable}{$col_ijc})
      if (MMisc::safe_exists(\%tables, $ctable, $col_ijc));

  my ($f) = &fix_entries($col_ijc, 1, $ijc);

  $tables{$ctable}{$col_ijc} = $f;
}

#####

sub add_usecolumn_to_table {
  my ($use) = @_;

  MMisc::error_quit("No table specified")
      if ($ctable eq "default");

  my ($f) = &fix_entries($col_use, 1, $use);

  push @{$tables{$ctable}{$col_use}}, $f;
}

#####

sub check_tables {
  MMisc::error_quit("Must have at least 2 tables to work")
      if (scalar(keys %tables) < 2);

  my $errtxt = "";
  foreach my $tab (@tord) {
    foreach my $key (@keys) {
      if (! MMisc::safe_exists(\%tables, $tab, $key)) {
        $errtxt .= "\n - For table \'$tab\', mandatory option \'$key\' was not set ?";
      }
    }
  }
  MMisc::error_quit("Problem with provided list of tables: $errtxt")
      if (! MMisc::is_blank($errtxt));
}

##########

sub get_csv_file_columns {
  my ($csvf) = @_;

  my $csvh = new CSVHelper();
  &csverr($csvh);
  my @h = $csvh->loadCSV_getheader($csvf);
  &csverr($csvh);

  return(@h);
}

#####

sub check_csv_columns {
  my $errtxt = "";
  foreach my $tab (@tord) {
    my $csvf = $tables{$tab}{$col_csv};
    my @cols = ();
    push @cols, $tables{$tab}{$col_ijc};
    push @cols, @{$tables{$tab}{$col_use}};

    my @fcols = &fix_entries("CSV File [$csvf]", 0, &get_csv_file_columns($csvf));
    my %tmp = MMisc::array1d_to_count_hash(\@fcols);
    foreach my $c (@cols) {
      if (! MMisc::safe_exists(\%tmp, $c)) {
        $errtxt .= " - Required column [$c] not found in CSV file [$csvf]\n";
        next;
      }
      if ($tmp{$c} > 1) {
        $errtxt .= " - Required column [$c] has multiple candidates (" 
          . $tmp{$c} . ") in CSV file [$csvf]\n";
      }
    }
  }
  MMisc::error_quit("Problem with provided CSV columns for tables: $errtxt")
      if (! MMisc::is_blank($errtxt));
}

####################

sub cp {
  my ($if, $of) = @_;

  my $err = MMisc::filecopy($if, $of);
  MMisc::error_quit($err) if (! MMisc::is_blank($err));
}

#####

sub step_filecopy {
  print "[*] Step " . $step++ . ": File copy\n";

  my @toload = ();
 foreach my $tab (@tord) {
    my $csv = $tables{$tab}{$col_csv};
    my ($err, $d, $f, $e) = MMisc::split_dir_file_ext($csv);
    MMisc::error_quit("Problem with table \'$tab\' \'$col_csv\' file ($csv) : $err")
        if (! MMisc::is_blank($err));
    
    my $of = MMisc::concat_dir_file_ext($wrkdir, $tab, "csv");
    print " +  From: $csv\n";
    print "      To: $of\n";
    &cp($csv, $of);
    push @toload, $of;
  }
  return(@toload);
}

#####

sub step_createselect {
  print "[*] Step " . $step++ . ": SELECT command generation\n";
  
  my @cols = ();
  push @cols, $tord[0] . "." . $tables{$tord[0]}{$col_ijc};
  push @csv_headers, $tables{$tord[0]}{$col_ijc};

  my @sel = ();
  foreach my $tab (@tord) {
    foreach my $use (@{$tables{$tab}{$col_use}}) {
      my $n = $tab . "." . $use;
      push @cols, $n;
      push @csv_headers, $n;
    }
    push @sel, $tab . "." . $tables{$tab}{$col_ijc};
  }

  my $cmd =
    "SELECT " . join(",", @cols)
      . " FROM " . join(" INNER JOIN ", @tord)
        . " WHERE " . join("=", @sel)
          ;

  print " => $cmd\n";

  my $of = "$wrkdir/select.cmd";
  MMisc::error_quit("Problem writing select command file ($of)")
      if (! MMisc::writeTo($of, "", 1, 0, $cmd));

  return($cmd);
}

#####

sub step_dbgen {
  print "[*] Step " . $step++ . ": DB generation\n";

  $db = "$wrkdir/DB.sql";
  my $logfile = "$wrkdir/DBgen.log";

  my $cmd = "$tool -f -D -M $db -o $wrkdir " . join(" ", @_);

  my ($ok, $txt, $so, $se, $rc, $logfile) 
    = MMisc::write_syscall_logfile($logfile, $cmd);

  MMisc::error_quit("Problem running tool, see: $logfile")
      if ($rc != 0);

  my $err = MMisc::check_file_r($db);
  MMisc::error_quit("Problem with database file ($db) : $err")
      if (! MMisc::is_blank($err));

  print "  -> Created [$db]\n";
}

#####

sub csverr {
  MMisc::error_quit("No CSV handler ?") if (! defined $_[0]);
  MMisc::error_quit("CSV handler problem: " . $_[0]->get_errormsg())
      if ($_[0]->error());
}

##

sub step_dooutcsv {
  print "[*] Step " . $step++ . ": CSV generation\n";

  my ($cmd) = @_;

  my $err = MMisc::check_file_r($db);
  MMisc::error_quit("Problem with database file ($db) : $err")
      if (! MMisc::is_blank($err));

  my ($err, $dbh) = MtSQLite::get_dbh($db);
  MMisc::error_quit("Problem with database ($db) : $err")
      if (! MMisc::is_blank($err));

  my ($err, $sth) = MtSQLite::get_command_sth($dbh, $cmd);
  MMisc::error_quit("Problem preparing SQL command : $err")
      if (! MMisc::is_blank($err));

  my $err = MtSQLite::execute_sth($sth);
  MMisc::error_quit("Problem running SQL command : $err")
    if (! MMisc::is_blank($err));
  
  # Prepare out csv file
  open FILE, ">$rescsv"
    or MMisc::error_quit("Problem with \'rescsv\' file ($rescsv) : $!");
  my $csvh = new CSVHelper();
  &csverr($csvh);
  $csvh->set_number_of_columns(scalar @csv_headers);
  &csverr($csvh);
  my $line = $csvh->array2csvline(@csv_headers);
  &csverr($csvh);
  print FILE "$line\n";
  
  # Read the matching records and print them out
  my $idc = 0;
  my $doit = 1;
  while ($doit) {
    my ($err, @data) = MtSQLite::sth_fetchrow_array($sth);
    MMisc::error_quit("Problem obtaining row: $err")
      if (! MMisc::is_blank($err));
    if (scalar @data == 0) {
      $doit = 0;
      next;
    }
    $line = $csvh->array2csvline(@data);
    &csverr($csvh);
    print FILE "$line\n";

    $idc++;
  }
  close FILE;

  my $err = MtSQLite::sth_finish($sth);
  MMisc::error_quit("Problem while completing statement: $err")
    if (! MMisc::is_blank($err));

  print "  -> Wrote [$rescsv] ($idc data entries)\n";
}

#####

sub doit {
  # First, copy all CSV files to the wrkdir using the to use table name
  my @tmp = &step_filecopy();
  
  # Then create the select command
  my $cmd = &step_createselect();

  # Then the DB
  &step_dbgen(@tmp);

  # CSV generation
  &step_dooutcsv($cmd);
}

####################

sub set_usage {  
  my $tmp=<<EOF
$versionid

$0 [--help | --version] [--Tool location] --wrkdir dir --rescsv file [--table tablename --csvfile csvfile --innerjoin columnname --usecolumn columnname] [--table ...] 

Will use DEVA_cli to perform an inner join select operation.

Where:
  --help     This help message
  --version  Version information
  --Tool     Location of the \'DEVA_cli\' tool
  --wrkdir   The directory where all DEVA work is performed
  --rescsv   The resulting CSV file
Each table needs to be defined as follow:
  --table    Specify the name of the table as it will be written in the resulting file
  --csvfile  Specify the file name containing the data to load into the table in a CSV format
  --innerjoin  Specify the name of the column that will be used to join with the next table (only keep elements present in both) (will appear as \'columnname\')
  --usecolumn  Specify the name of the column to print in the resulting CSV file (will appear as \'tablename.columnname\')

Note: \'columnname\' and \'tablename\' will be adapted if they do not match proper SQLite usage.

Note: Only the first \'innerjoin\' \'columnname\' will be printed in the resulting CSV file

EOF
;

  return($tmp);
}

