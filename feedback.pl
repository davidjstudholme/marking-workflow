#!/usr/bin/env perl
use strict;
use warnings;
use Encode qw(decode);

# Usage:
#   perl feedback.pl input.tsv > reports.txt
#
# Columns (case-insensitive):
#   section
#   text_in_suggestions_if_no
#   text_if_no
#   text_if_yes
#   question_or_criterion
#   <candidate columns...>

my $file = shift or die "Usage: $0 input.tsv\n";
open my $fh, "<:raw", $file or die "Cannot open $file: $!";

# ----------------------------
# Helpers
# ----------------------------
sub clean_cell {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/\r$//;
    $s =~ s/\x{A0}/ /g;       # NBSP -> space
    $s =~ s/^\s+|\s+$//g;     # trim
    $s =~ s/^"+|"+$//g;
    return $s;
}

sub lc_cell { return lc(clean_cell($_[0])); }

sub candidate_short_label {
    my ($raw) = @_;
    $raw = clean_cell($raw);
    #return $1 if $raw =~ /^(\d+)_/;
    return $raw || "candidate";
}

sub is_yes { lc_cell($_[0]) eq 'yes' }
sub is_no  { lc_cell($_[0]) eq 'no'  }
sub is_na  { lc_cell($_[0]) eq 'na'  }

sub is_trivial_boolish {
    my ($s) = @_;
    $s = lc_cell($s);
    return 1 if $s eq '' || $s eq 'yes' || $s eq 'no' || $s eq 'na';
    return 0;
}

# Identify the "overall grade" row robustly
sub is_overall_grade_question {
    my ($q) = @_;
    $q = clean_cell($q);
    $q =~ s/^"+|"+$//g;      # strip surrounding quotes if present
    $q =~ s/^\s+//;
    return ($q =~ /^Overall\b/i) ? 1 : 0;
}

# Identify the "candidate number" row
sub is_candidate_number_question {
    my ($q) = @_;
    $q = lc_cell($q);
    $q =~ s/^"+|"+$//g;
    return ($q eq 'candidate number') ? 1 : 0;
}

# Identify the "candidate number" row
sub is_sra_accessions_question {
    my ($q) = @_;
    $q = lc_cell($q);
    $q =~ s/^"+|"+$//g;
    return ($q =~ m/SRA accession numbers$/i) ? 1 : 0;
}

# Body text renderer:
# - yes -> text_if_yes (if present) else nothing
# - no  -> text_if_no  (if present) else nothing
# - other -> raw answer (free text)
sub render_body_text {
    my (%a) = @_;
    my $ans = clean_cell($a{answer});
    return undef if $ans eq '' || is_na($ans);

    my $t_yes = clean_cell($a{text_if_yes});
    my $t_no  = clean_cell($a{text_if_no});

    if (is_yes($ans)) {
        return $t_yes if $t_yes ne '';
        return undef;
    } elsif (is_no($ans)) {
        return $t_no if $t_no ne '';
        return undef;
    } else {
        return $ans;
    }
}

# Suggestion renderer:
# If answer == "no" and text_in_suggestions_if_no is meaningful -> suggest it.
sub render_suggestion {
    my (%a) = @_;

    my $ans = clean_cell($a{answer});
    return undef if $ans eq '' || is_na($ans);
    return undef unless is_no($ans);

    my $t = clean_cell($a{text_in_suggestions_if_no});
    return undef if is_trivial_boolish($t);

    return $t;
}

# ----------------------------
# Read header and locate columns
# ----------------------------
my $header = <$fh>;
defined $header or die "Empty file\n";
$header = decode('UTF-8', $header);
chomp $header;
$header =~ s/\r$//;

my @h = map { clean_cell($_) } split /\t/, $header, -1;

my %col;
for my $i (0 .. $#h) {
    $col{ lc($h[$i]) } = $i;
}

sub require_col {
    my (@names) = @_;
    for my $n (@names) {
        my $k = lc($n);
        return $col{$k} if exists $col{$k};
    }
    die "Missing required column. Tried: " . join(", ", @names) . "\nFound headers: " . join(" | ", @h) . "\n";
}

my $i_section = require_col('section');
my $i_sugg_no = require_col('text_in_suggestions_if_no');
my $i_no      = require_col('text_if_no');
my $i_yes     = require_col('text_if_yes');
my $i_q       = require_col('question_or_criterion');

my $first_cand = $i_q + 1;
die "No candidate columns detected (expected candidate columns after question_or_criterion)\n"
  if $first_cand > $#h;

my @candidate_keys = @h[$first_cand .. $#h];

my %candidate_label = map { $_ => candidate_short_label($_) } @candidate_keys;
my %overall_grade;  # per candidate
my %sra_accessions; # per candidate


# ----------------------------
# Parse rows
# ----------------------------
my %rows_by_section;
my @section_order;
my %seen_section;

while (my $line = <$fh>) {
    $line = decode('UTF-8', $line);
    chomp $line;
    $line =~ s/\r$//;
    next if $line =~ /^\s*$/;

    my @c = map { clean_cell($_) } split /\t/, $line, -1;

    my $section = $c[$i_section] // '';
    $section = $section ne '' ? $section : 'Uncategorised';

    if (!$seen_section{$section}++) {
        push @section_order, $section;
    }

    my $qtext = $c[$i_q] // '';

    my %row = (
        section                   => $section,
        text_in_suggestions_if_no => ($c[$i_sugg_no] // ''),
        text_if_no                => ($c[$i_no]      // ''),
        text_if_yes               => ($c[$i_yes]     // ''),
        question_or_criterion     => $qtext,
        answers                   => {},
    );

    for my $ci (0 .. $#candidate_keys) {
        my $cand_key = $candidate_keys[$ci];
        my $ans = $c[$first_cand + $ci] // '';
        $row{answers}{$cand_key} = $ans;
    }

    # Capture candidate number for nicer label
    if (is_candidate_number_question($qtext)) {
        for my $ci (0 .. $#candidate_keys) {
            my $cand_key = $candidate_keys[$ci];
            my $raw = $c[$first_cand + $ci] // '';
            my $label = candidate_short_label($raw);
            $candidate_label{$cand_key} = $label if $label ne '';
        }
    }

    # Capture overall grade (do NOT print it as a bullet later)
    if (is_overall_grade_question($qtext)) {
        for my $ci (0 .. $#candidate_keys) {
            my $cand_key = $candidate_keys[$ci];
            my $grade = clean_cell($c[$first_cand + $ci] // '');
            $overall_grade{$cand_key} = $grade if $grade ne '';
        }
        $row{_suppress_in_body} = 1;
    }

    # Capture SRA accessions (do NOT print it as a bullet later)    
    if (is_sra_accessions_question($qtext)) {
        for my $ci (0 .. $#candidate_keys) {
            my $cand_key = $candidate_keys[$ci];
            my $sra_accs = clean_cell($c[$first_cand + $ci] // '');
            $sra_accessions{$cand_key} = $sra_accs if $sra_accs ne '';
	    warn "SRA =>'$sra_accs";
	}
        $row{_suppress_in_body} = 1;
    }
        
    push @{ $rows_by_section{$section} }, \%row;
}

close $fh;

# ----------------------------
# Output reports to STDOUT
# ----------------------------
for my $cand_key (@candidate_keys) {
    my $label = $candidate_label{$cand_key} // $cand_key;

    my $outfilename = "$label.feedback.txt";
    warn "Will write to file: $outfilename\n";
    open my $outfile, ">", $outfilename or die "Could not open '$outfilename': $!";
    
    my @suggestions;
    my %seen_s;
    my %already_printed;

    print $outfile "=" x 70, "\n";
    print $outfile "Candidate: $label\n";
    print $outfile "=" x 70, "\n";

    # Report the published results for these datasets
    if (exists $overall_grade{$cand_key} && $overall_grade{$cand_key} ne '') {
	my $grade = $overall_grade{$cand_key};
        print $outfile "Overall, this poster represents $grade work. ";

	if ($grade =~ m/Outstanding|Exceptional|Excellent/i) {
	    print $outfile "Well done! You have significantly exceeded the standard expected of a good student at Y2 undergraduate level for this work.";
	}
	elsif ($grade =~ m/Very good/i) {
	    print $outfile "Well done! You have exceeded the standard expected of a good student at Y2 undergraduate level for this work.";
	}
	elsif ($grade =~ m/Fairly good/i) {
	    print $outfile "Your poster exhibits some minor deficiencies, but falls only slightly below the expected standard for a good student work at this level. Please see the comments below and any additional comments annotated directly on your submitted document.";
	}
	elsif ($grade =~ m/Good/i) {
	    print $outfile "Well done. You have met the standard expected of a good student at Y2 undergraduate level for this work. There are no significant problems or deficiencies.";
	}
	elsif ($grade =~ m/Competent|Fairly competent|Adequate/i) {
	    print $outfile "Please see the comments below and any additional comments annotated directly on your submitted document to see how your work could be improved.";
	    
	}
	elsif ($grade =~ m/Weak|Fail/i) {
	    print $outfile "There were significant weaknesses in this work; please see the comments below and any comments that have been annoated onto your submitted document.";
	}
	else {
	    die "Could not interpret the overall grading: '$grade'";
	}
	print $outfile "\n";

    }

    if (exists $sra_accessions{$cand_key} && $sra_accessions{$cand_key} ne '') {
	print $outfile "You analysed these SRA accessions:$sra_accessions{$cand_key}.\n";
	if ( $sra_accessions{$cand_key} =~ m/(SRR\d+).*\s+(SRR\d+)/) {
	    my $sra_accessions = [$1, $2]; 
	    my $hu_result = check_sra_against_hu_et_al($sra_accessions);
	    print $outfile "$hu_result\n";
	} else {
	    die "Could not parse SRA accessions from '$sra_accessions{$cand_key}'\n";
	}
    }
    
    for my $section (@section_order) {
        next unless exists $rows_by_section{$section};

        my @lines;

        for my $row (@{ $rows_by_section{$section} }) {
            my $ans = $row->{answers}{$cand_key};

            # Suppress the overall-grade row from body bullets (we print it at top)
            next if $row->{_suppress_in_body};

            my $body = render_body_text(
                answer      => $ans,
                text_if_yes => $row->{text_if_yes},
                text_if_no  => $row->{text_if_no},
            );

            if (defined $body && $body ne '') {
                push @lines, $body;
                $already_printed{$body} = 1;
            }

            my $s = render_suggestion(
                answer                    => $ans,
                text_in_suggestions_if_no => $row->{text_in_suggestions_if_no},
            );

            if (defined $s && $s ne '' && !$already_printed{$s} && !$seen_s{$s}++) {
                push @suggestions, $s;
            }
        }

        next unless @lines;

        print $outfile "\n$section\n";
        print $outfile "-" x length($section), "\n";
        print $outfile "• $_\n" for @lines;
    }

    if (@suggestions) {
        print $outfile "\nIn addition to the feedback here, please also check for comments added onto your submitted (PDF) file.\n";
        print $outfile "\nSuggestions for improvement\n";
        print $outfile "---------------------------\n";
	
	# Report the published results for these datasets
	if (exists $overall_grade{$cand_key} && $overall_grade{$cand_key} ne '') {
	    my $grade = $overall_grade{$cand_key};
	    if ($grade =~ m/Outstanding|Exceptional|Excellent|Very good/i) {
		print $outfile "Even though you exceeded the requirements for good work, here are some suggestions on how itthe poster could be improved even further.\n";
	    }
	    elsif ($grade =~ m/Fairly good/i) {
	    }
	    elsif ($grade =~ m/Good/i) {
		print $outfile "Even though your work is already good, here are some suggestions on how the poster could be improved even further.";
	    }
	    elsif ($grade =~ m/Competent|Fairly competent|Adequate/i) {
		print $outfile "Please see the comments below and any additional comments annotated directly on your submitted document to see how your work could be improved.";
	    }
	    elsif ($grade =~ m/Weak|Fail/i) {
	    }
	    else {
		die "Could not interpret the overall grading: '$grade'";
	    }
	    print "\n";
	    
	}

        print $outfile "• $_\n" for @suggestions;
    }

    print $outfile "\n";
    close $outfile;

    warn "Wrote reports to $outfilename\n";
}

sub check_sra_against_hu_et_al {
    use Text::CSV;
    my $sra_accessions = shift or die "Failed to specify SRA accession(s) as argument";
    my $sra_file = 'SRA_run_table.csv';
    my $hpv_file = 'HPV_types_in_each_sample.csv';
    my %sra2biosample;
    my %sra2name;
    my %name2hpv;
    my %name2sra;
    my $result_string = '';
    
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
    
    $result_string .= "I checked your results against Supplementary Table 4 of Hu et al. (2015).\n";
    $result_string .= "According to Hu et al. 2015 and the metadata on the NCBI website:\n";
    
    while (my $sra = shift @$sra_accessions) {
	my $name = $sra2name{$sra};
	my $biosample = $sra2biosample{$sra};
	my $hpv_list = $name2hpv{$name};
	$result_string .= "\t- $sra is sample $name (BioSample $biosample) and contains HPV $hpv_list.\n";
    }
    return($result_string);
}
