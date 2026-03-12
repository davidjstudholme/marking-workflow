#!/usr/bin/perl -w

use strict;
use warnings;
use Text::CSV;

my $usage = "$0 <SRA run accession number(s)>";
die "$usage\n" unless defined ($ARGV[0]);


my $sra_file = 'SRA_run_table.csv';
my $hpv_file = 'HPV_types_in_each_sample.csv';

my %sra2biosample;
my %sra2name;
my %name2hpv;
my %name2sra;


open my $fh, "<:utf8", $sra_file or die "Could not open '$sra_file': $!";
my $csv = Text::CSV->new({
    binary => 1,        # allow special characters
    auto_diag => 1,     # print errors automatically
			 });
while (my $row = $csv->getline($fh)) {
    # $row is an array reference
    my @fields = @$row;
    my ($run, $bases, $biosample, $library_name) = @fields;
    if ($library_name =~ m/HUM\w+\-\d+\-([\w\d]+)/) {
	#warn "$run => $1\n";
	$sra2name{$run}= $1;
	$name2sra{$1}=$run;
    }			
    if ($biosample =~ m/(SAMN\d+)/) {
	#warn "$run => $1\n";
	$sra2biosample{$run} = $biosample;
    }    
}
close $fh;

open $fh, "<:utf8", $hpv_file or die "Could not open '$hpv_file': $!";
$csv = Text::CSV->new({
    binary => 1,        # allow special characters
    auto_diag => 1,     # print errors automatically
			 });
while (my $row = $csv->getline($fh)) {
    # $row is an array reference
    my @fields = @$row;
    my ($name, $hpv_list) = @fields;

    if (defined $name2sra{$name}) {
	#warn "Getting HPV types for sample $name\n";
    }
    $hpv_list =~ s/\s*\"\s*//g;
    #warn "\t$name => '$hpv_list'\n";
    $name2hpv{$name} = $hpv_list;
}
close $fh;




print" You can check your results against Supplementary Table 4 of Hu et al. (2015).";
print "According to Hu et al. 2015 and the metadata on the NCBI website:\n";

while (my $sra = shift @ARGV) {
    my $name = $sra2name{$sra};
    my $biosample = $sra2biosample{$sra};
    my $hpv_list = $name2hpv{$name};
    print "\t$sra is sample $name (BioSample $biosample) and contains HPV $hpv_list.\n";
}
print "\n";    
