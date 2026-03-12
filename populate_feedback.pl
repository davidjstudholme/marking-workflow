#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Text::CSV;
use File::Spec;
use Encode qw(decode);

# -----------------------------
# Configuration / command line
# -----------------------------
# Usage:
#   perl populate_feedback.pl input.csv feedback_dir output.csv
#
# Example:
#   perl populate_feedback.pl submissions.csv feedback_txt/ submissions_with_feedback.csv

my ($input_csv, $feedback_dir, $output_csv) = @ARGV;

die "Usage: perl $0 input.csv feedback_dir output.csv\n"
    unless defined $input_csv && defined $feedback_dir && defined $output_csv;

# -----------------------------
# Build lookup of feedback files
# -----------------------------
opendir(my $dh, $feedback_dir) or die "Cannot open directory '$feedback_dir': $!";

my %feedback_for;   # key = "CandidateNumber_SubmissionId" => full path

while (my $file = readdir($dh)) {
    next if $file =~ /^\.\.?$/;
    next unless $file =~ /\.feedback\.txt$/i;

    # Capture just the leading candidate+submission part.
    # Works for:
    #   327665_Xa94217e9.feedback.txt
    #   308097_X1b556a5f_1_bfc.feedback.txt
    if ($file =~ /^(\d+_X[[:alnum:]]+)/) {
        my $key = $1;
        my $path = File::Spec->catfile($feedback_dir, $file);

        if (exists $feedback_for{$key}) {
            warn "Duplicate feedback match for key '$key':\n",
                 "  existing: $feedback_for{$key}\n",
                 "  ignoring: $path\n";
            next;
        }

        $feedback_for{$key} = $path;
    }
    else {
        warn "Filename did not match expected pattern, skipping: $file\n";
    }
}

closedir($dh);

# -----------------------------
# Set up CSV reader/writer
# -----------------------------
my $csv_in = Text::CSV->new({
    binary            => 1,
    auto_diag         => 1,
    sep_char          => ',',
    allow_loose_quotes => 1,
});

my $csv_out = Text::CSV->new({
    binary    => 1,
    auto_diag => 1,
    sep_char  => ',',
    eol       => "\n",
});

open(my $in_fh, "<:encoding(utf-8)", $input_csv)
    or die "Cannot open input CSV '$input_csv': $!";

open(my $out_fh, ">:encoding(utf-8)", $output_csv)
    or die "Cannot open output CSV '$output_csv': $!";

my $header = $csv_in->getline($in_fh)
    or die "Could not read header row from '$input_csv'\n";

$csv_out->print($out_fh, $header);

my %col_index;
for my $i (0 .. $#$header) {
    $col_index{$header->[$i]} = $i;
}

for my $required ("Candidate Number", "Submission id", "Feedback comment") {
    die "Required column '$required' not found in CSV header\n"
        unless exists $col_index{$required};
}

# -----------------------------
# Process rows
# -----------------------------
my $row_count      = 0;
my $matched_count  = 0;
my $missing_count  = 0;

while (my $row = $csv_in->getline($in_fh)) {
    $row_count++;

    # Insert dummy grade
    $row->[ $col_index{"Grade"} ] = 0;
    
    my $candidate_num = $row->[ $col_index{"Candidate Number"} ] // '';
    my $submission_id = $row->[ $col_index{"Submission id"} ]    // '';

    $candidate_num =~ s/^\s+|\s+$//g;
    $submission_id =~ s/^\s+|\s+$//g;

    my $key = $candidate_num . "_" . $submission_id;
    
    if (exists $feedback_for{$key}) {
        my $feedback_path = $feedback_for{$key};
	
        open(my $txt_fh, "<:raw", $feedback_path)
            or die "Cannot open feedback file '$feedback_path': $!";
	
        local $/;
        my $content = <$txt_fh>;
        close($txt_fh);
	
        # Decode as UTF-8; invalid bytes become warnings if truly broken.
        $content = decode("UTF-8", $content, 1);

        # Normalise line endings to Unix style; CSV will preserve embedded newlines.
        $content =~ s/\r\n/\n/g;
        $content =~ s/\r/\n/g;

	# Change linebreaks to HTML breaks for benefit of Moodle
	$content =~ s/\n/<br>/g;

	# Infer grade from content
	my $percentage_mark = 99;
	if ($content =~ m/Overall, this poster represents\s+(.*?)\s+work\./i) {
	    my $grade = $1;
	    warn "Grade: $grade\n";
	    if ($grade =~ m/\((\d+)\)/) {
		$percentage_mark = $1;
	    } elsif ($grade =~m/Very\s+good/i) {
		$percentage_mark = 68;
	    } elsif ($grade =~m/Fairly\s+good/i) {
                $percentage_mark = 62;
	    } elsif ($grade =~m/Good/i) {
                $percentage_mark = 65;
	    } elsif ($grade =~m/Fairly\s+competent/i) {
                $percentage_mark = 55;
	    } elsif ($grade =~m/Competent/i) {
                $percentage_mark = 58;
	    } elsif ($grade =~m/Adequate/i) {
                $percentage_mark = 52;
	    } else {
		die "Could not infer percentage mark for '$grade'\n";
	    }
	    warn "$grade => $percentage_mark\n\n";
	    $row->[ $col_index{"Grade"} ] = $percentage_mark;
	}
	
        $row->[ $col_index{"Feedback comment"} ] = $content;
        $matched_count++;
    }
    else {
        warn "No feedback file found for CSV row key '$key'\n";
        $missing_count++;
    }

    $csv_out->print($out_fh, $row);
}

close($in_fh);
close($out_fh);

print "Done.\n";
print "Rows processed: $row_count\n";
print "Rows matched:   $matched_count\n";
print "Rows missing:   $missing_count\n";
print "Output written: $output_csv\n";
