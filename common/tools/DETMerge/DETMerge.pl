#!/bin/sh
#! -*-perl-*-
eval 'exec env PERL_PERTURB_KEYS=0 PERL_HASH_SEED=0 perl -x -S $0 ${1+"$@"}'
  if 0;

#
# $Id$
#
# DETMerge
# DETMerge.pl
# Authors: Jonathan Fiscus
#          Jerome Ajot
#          Martial Michel
# 
# This software was developed at the National Institute of Standards and
# Technology by employees of the Federal Government in the course of
# their official duties.  Pursuant to Title 17 Section 105 of the United
# States Code this software is not subject to copyright protection within
# the United States and is in the public domain. 
#
# It is an experimental system.  
# NIST assumes no responsibility whatsoever for its use by any party, and makes no guarantees,
# expressed or implied, about its quality, reliability, or any other characteristic.
#
# We would appreciate acknowledgement if the software is used.  This software can be
# redistributed and/or modified freely provided that any derivative works bear some notice
# that they are derived from it, and any modified versions bear some notice that they
# have been modified.
# 
# THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST
# MAKES NO EXPRESS OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER,
# INCLUDING MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE.

use strict;
use Data::Dumper;

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

use TrialsFuncs;

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
foreach my $pn ("MMisc", "DETCurve", "DETCurveSet") {
  unless (eval "use $pn; 1") {
    my $pe = &eo2pe($@);
    &_warn_add("\"$pn\" is not available in your Perl installation. ", $partofthistool, $pe);
    $have_everything = 0;
  }
}

# usualy part of the Perl Core
foreach my $pn ("Getopt::Long", "Pod::Usage", "File::Temp") {
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

my $VERSION = 0.1;
my $man = 0;
my $help = 0;
my $title = "Combined DET Curve";
my $titleRegex = undef;
my @inputSrl = ();
my $outputSrl = undef;
my $gzipPROG = "gzip";
my $mergeType = "blocked";
my $v = 0;

Getopt::Long::Configure(qw( no_ignore_case ));

GetOptions
  (
   'o|output-srl=s'  => \$outputSrl,
   
   't|title=s'       => \$title,
   
   'Z|ZipPROG=s'     => \$gzipPROG,

   'M|MergeType=s'   => \$mergeType,	

   'version'         => sub { my $name = $0; $name =~ s/.*\/(.+)/$1/; print "$name version $VERSION\n"; exit(0); },
   'h|help'          => \$help,
   'v|verbose'       => \$v,
   'm|man'           => \$man,
  );

## Docs
pod2usage(1) if $help;
pod2usage(-exitvalue => 0, -verbose => 2) if $man;
##

## Checking inputs
pod2usage("Error: At least one DET Curve must be specified.\n") if(scalar ( @ARGV ) == 0);
@inputSrl = @ARGV;
pod2usage("ERROR: The output must be specified via -o\n") if (! defined($outputSrl));

my $trial = undef;
my $firstDet = undef;

foreach my $inDet (@inputSrl){
  print "Loadind DETCurve '$inDet'\n" if ($v > 0);
  my $det = DETCurve::readFromFile($inDet, $gzipPROG);
  
  if (! defined($firstDet)){
    $firstDet = $det;
  }

  ### First Check Compatability
#  die "Error: dets /$inputSrl[0]/ and /$inDet/ are not compatable"
#     if (! $firstDet->isCompatible($det));
  
  ### Set the Trial metrics based on the metricType
  TrialsFuncs::mergeTrials(\$trial, $det->getTrials(), $firstDet->getMetric(), $mergeType);

}
  
### Do the merge based on the merge type
#print Dumper($trial);  

### Make a metric clone
my $metric = $firstDet->getMetric()->cloneForTrial($trial);

### delete the .gz if it's there
$outputSrl =~ s/\.gz$//;

my $outDet = new DETCurve($trial, $metric, $title, [()], $gzipPROG);
print "Computing points\n" if ($v > 0);
$outDet->computePoints();

print "Writing to '$outputSrl'\n" if ($v > 0);
$outDet->serialize($outputSrl);

exit 0;

#############################################  End of the program #########################################

sub _warn_add
{
	$warn_msg .= "[Warning] " . join(" ", @_) . "\n";
}

__END__

=head1 NAME

DETMerge.pl -- Merge multiple serialized DET Curve.

=head1 SYNOPSIS

B<DETMerge.pl> [--help | --man | --version] [--verbose] --output-srl file [--title "title"] [--ZipPROG prog] [--MergeType type] input_srl [input_srl [...]]

=head1 DESCRIPTION

The script merge multiple serialized DET Curve generated by the F4DE package.

=head1 OPTIONS

=over

=item B<--output-srl> 

Specifiy the output file.

=item B<--title> S<"title">

Specify a new title.

=item B<--ZipPROG> F<GZIP_PATH>

Specify the full path name to gzip (default: 'gzip').

=item B<--MergeType> I<type>

Specify the type of merge to perform

=item B<--help>

Print the help.

=item B<--man>

Print the manual.

=item B<--version>

Print the version number.

=back

=head1 BUGS

No known bugs.

=head1 NOTES

The default iso-cost ratio coefficients (-R option) and iso-metric coefficients (-Q option) are defined into the metric.

=head1 AUTHOR

 Jonathan Fiscus <jonathan.fiscus@nist.gov>
 Jerome Ajot <jerome.ajot@nist.gov>
 Martial Michel <martial.michel@nist.gov>

=head1 VERSION

DETUtil.pl version 0.4

=head1 COPYRIGHT 

This software was developed at the National Institute of Standards and Technology by employees of the Federal Government in the course of their official duties.  Pursuant to Title 17 Section 105 of the United States Code this software is not subject to copyright protection within the United States and is in the public domain. It is an experimental system.  NIST assumes no responsibility whatsoever for its use by any party.

THIS SOFTWARE IS PROVIDED "AS IS."  With regard to this software, NIST MAKES NO EXPRESS OR IMPLIED WARRANTY AS TO ANY MATTER WHATSOEVER, INCLUDING MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE.

=cut
