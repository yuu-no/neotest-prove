#!/usr/bin/env perl

# neotest-prove helper.
#
# Runs `prove`, capturing the raw per-file TAP that Test::Harness dumps when
# PERL_TEST_HARNESS_DUMP_TAP is set, parses it with TAP::Parser, and writes
# structured results as JSON for the neotest-prove Lua adapter.
#
# Usage: perl neotest-prove-runner.pl --results <json> -- <prove> [args...]
#
# Only core modules are used (Perl 5.10.1+). JSON is hand-encoded.

use strict;
use warnings;
use File::Temp ();
use File::Find ();
use TAP::Parser ();

my ( $results_path, @prove_cmd );
{
    my @argv = @ARGV;
    while ( defined( my $arg = shift @argv ) ) {
        if ( $arg eq '--results' ) {
            $results_path = shift @argv;
        }
        elsif ( $arg eq '--' ) {
            @prove_cmd = @argv;
            last;
        }
    }
}
die "neotest-prove: --results <path> is required\n" unless defined $results_path;
die "neotest-prove: missing prove command after '--'\n" unless @prove_cmd;

my $dump = File::Temp->newdir( CLEANUP => 1 );
my $exit;
{
    local $ENV{PERL_TEST_HARNESS_DUMP_TAP} = "$dump";
    my $status = system @prove_cmd;
    $exit = $status == -1 ? 1 : ( $status >> 8 );
}

my %files;
File::Find::find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless -f $_;
            my $rel = substr $_, length "$dump";
            $rel =~ s{^/+}{};
            $files{ '/' . $rel } = parse_tap_file($_);
        },
    },
    "$dump",
);

write_json( $results_path, \%files );
exit $exit;

# Parse one dumped TAP file into { status, errors, subtests }.
sub parse_tap_file {
    my ($path) = @_;
    my $parser = TAP::Parser->new( { tap => read_file($path) } );

    my @lines;
    while ( my $result = $parser->next ) {
        push @lines, $result->raw;
    }

    my $status =
        $parser->skip_all     ? 'skipped'
      : $parser->has_problems ? 'failed'
      :                         'passed';

    my %file = ( status => $status, errors => [], subtests => {} );
    parse_subtests( \@lines, \%file );
    return \%file;
}

# Walk raw TAP lines, recording subtest results and failure diagnostics.
# Subtests nest by 4-space indentation; a `# Subtest: NAME` comment opens one
# and a same-indent `ok N - NAME` line closes it.
sub parse_subtests {
    my ( $lines, $file ) = @_;
    my @stack;          # innermost-last
    my %pending_msg;    # indent => message for the next "at ... line" line

    for my $line (@$lines) {
        my ($ws) = $line =~ /^(\s*)/;
        my $indent = length $ws;

        if ( $line =~ /^\s*#\s*Subtest:\s*(.+?)\s*$/ ) {
            my $name  = $1;
            my @names = map { $_->{name} } @stack;
            push @names, $name;
            push @stack,
              {
                name           => $name,
                marker_indent  => $indent,
                content_indent => $indent + 4,
                names          => \@names,
                errors         => [],
              };
            next;
        }

        if ( $line =~ /^\s*(not\s+)?ok\b\s*\d*\s*(?:-\s*)?(.*)$/ ) {
            my $failed = defined $1;
            my $rest   = $2;
            ( my $desc = $rest ) =~ s/\s*#.*$//;
            $desc =~ s/^\s+//;
            $desc =~ s/\s+$//;
            if (   @stack
                && $indent == $stack[-1]{marker_indent}
                && $desc eq $stack[-1]{name} )
            {
                my $st = pop @stack;
                my $status =
                    $rest =~ /#\s*skip/i ? 'skipped'
                  : $failed              ? 'failed'
                  :                        'passed';
                $file->{subtests}{ join '::', @{ $st->{names} } } = {
                    status => $status,
                    errors => $st->{errors},
                };
            }
            next;
        }

        if ( $line =~ /^\s*#\s*Failed test\b(.*)$/ ) {
            ( my $msg = "Failed test$1" ) =~ s/\s+$//;
            $pending_msg{$indent} = $msg;
            next;
        }

        if ( $line =~ /^\s*#\s*at\s+\S+\s+line\s+(\d+)/ ) {
            my $msg = delete $pending_msg{$indent};
            $msg = 'Test failed' unless defined $msg;
            add_error( $file, \@stack, $indent, $msg, $1 );
            next;
        }
    }
}

# Attach an error to the subtest whose body sits at the given indent, or to
# the file when no such subtest is open.
sub add_error {
    my ( $file, $stack, $indent, $msg, $lineno ) = @_;
    my $err = { message => $msg, line => $lineno + 0 };
    for my $st (@$stack) {
        if ( $st->{content_indent} == $indent ) {
            push @{ $st->{errors} }, $err;
            return;
        }
    }
    push @{ $file->{errors} }, $err;
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or return '';
    local $/;
    my $content = <$fh>;
    close $fh;
    return defined $content ? $content : '';
}

sub write_json {
    my ( $path, $files ) = @_;
    open my $fh, '>', $path or die "neotest-prove: cannot write $path: $!\n";
    print {$fh} encode_files($files);
    close $fh;
}

sub encode_files {
    my ($files) = @_;
    my @parts;
    for my $path ( sort keys %$files ) {
        push @parts, json_str($path) . ':' . encode_file( $files->{$path} );
    }
    return '{"files":{' . join( ',', @parts ) . '}}';
}

sub encode_file {
    my ($f) = @_;
    my @subs;
    for my $key ( sort keys %{ $f->{subtests} } ) {
        push @subs, json_str($key) . ':' . encode_result( $f->{subtests}{$key} );
    }
    return
        '{"status":'
      . json_str( $f->{status} )
      . ',"errors":'
      . encode_errors( $f->{errors} )
      . ',"subtests":{'
      . join( ',', @subs ) . '}}';
}

sub encode_result {
    my ($r) = @_;
    return
        '{"status":'
      . json_str( $r->{status} )
      . ',"errors":'
      . encode_errors( $r->{errors} ) . '}';
}

sub encode_errors {
    my ($errors) = @_;
    return '['
      . join( ',',
        map { '{"message":' . json_str( $_->{message} ) . ',"line":' . ( $_->{line} + 0 ) . '}' }
          @$errors )
      . ']';
}

sub json_str {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/([\\"])/\\$1/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    $s =~ s/([\x00-\x1f])/sprintf '\\u%04x', ord $1/ge;
    return '"' . $s . '"';
}
