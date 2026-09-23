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
use POSIX qw(WEXITSTATUS WIFSIGNALED WTERMSIG);
use TAP::Parser ();

# TAP fragments shared by the parsing subs below, so the places that match
# the same thing cannot drift apart. Declared up here because the TAP parsing
# below runs before later file-scope statements.
#
# The leading part of a TAP test line, up to its description: captures the
# "not " of a failure (undef on a pass); the description and any directive
# follow the match.
my $OK_LINE = qr/^\s*(not\s+)?ok\b\s*\d*\s*(?:-\s*)?/;

# Failure-location fragment of every "at FILE line N" form. Captures the file
# and the line number.
my $AT_LINE = qr/at\s+(\S+)\s+line\s+(\d+)/;

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
    $exit =
        $status == -1        ? 1
      : WIFSIGNALED($status) ? 128 + WTERMSIG($status)
      :                        WEXITSTATUS($status);
}

my %files;
File::Find::find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless -f $_;
            my $rel = substr $_, length "$dump";
            $rel =~ s{^/+}{};
            my $path = '/' . $rel;

            # `write_json` only runs once every file has been parsed, so a die
            # in here would drop the results of every *other* file in the same
            # run. Contain it to the one file it belongs to.
            my $parsed = eval { parse_tap_file( $_, $path ) };
            unless ($parsed) {
                ( my $err = $@ || 'unknown error' ) =~ s/\s+\z//;
                $parsed = unparsable_result("neotest-prove: could not parse TAP: $err");
            }
            $files{$path} = $parsed;
        },
    },
    "$dump",
);

write_json( $results_path, \%files );
exit $exit;

# Parse one dumped TAP file into { status, errors, subtests }. `$test_path` is
# the path of the test file the dump belongs to, used to tell that file's
# failure locations apart from ones reported in other files.
sub parse_tap_file {
    my ( $path, $test_path ) = @_;
    my $tap = read_file($path);

    # A file that produced no TAP at all -- a compile error, an early `exit` --
    # makes TAP::Parser die with "PANIC: could not determine iterator for
    # input", so report it instead of handing an empty string over.
    return unparsable_result('No TAP output') unless $tap =~ /\S/;

    my $parser = TAP::Parser->new( { tap => $tap } );

    my @lines;
    while ( my $result = $parser->next ) {
        push @lines, $result->raw;
    }

    my $status =
        $parser->skip_all     ? 'skipped'
      : $parser->has_problems ? 'failed'
      :                         'passed';

    my %file = ( status => $status, errors => [], subtests => {} );
    parse_subtests( \@lines, \%file, $test_path );
    return \%file;
}

# A file result standing in for TAP that could not be parsed.
sub unparsable_result {
    my ($message) = @_;
    return {
        status   => 'failed',
        errors   => [ { message => $message, line => undef } ],
        subtests => {},
    };
}

# Walk raw TAP lines, recording subtest results and failure diagnostics.
# Subtests nest by 4-space indentation and open in one of two forms:
#   - Test::More style: a `# Subtest: NAME` comment opens one and a
#     same-indent `ok N - NAME` line closes it.
#   - Test2::V0 style: a `(not )?ok N - NAME {` line opens one and a
#     same-indent, bare `}` line closes it. Test2 buffers subtest output, so
#     pass/fail is already known from the opening line; a subtest skipped in
#     its entirety instead reports that on a nested `1..0 # SKIP ...` plan
#     line, which is detected separately while the subtest body is open.
#
# A `(not )?ok ... {` line is only treated as a real Test2 opener when
# `find_brace_pairs` has matched it to a later bare `}` at the same indent
# (see below) -- an ordinary assertion whose description happens to end in a
# literal "{" has no such closer and falls through to plain ok/not-ok
# handling instead.
sub parse_subtests {
    my ( $lines, $file, $test_path ) = @_;
    my ( $brace_open, $brace_close ) = find_brace_pairs($lines);
    my @stack;          # innermost-last
    my %pending_msg;    # indent => message for the next "at ... line" line
    my $active_err;     # last recorded error, still collecting diagnostics
    my $active_indent;

    for my $i ( 0 .. $#$lines ) {
        my $line = $lines->[$i];
        my ($ws) = $line =~ /^(\s*)/;
        my $indent = length $ws;

        # Diagnostic comments that directly follow a recorded failure (e.g.
        # Test::More's "got:/expected:", Test::Deep's "Compared ...", Test2's
        # comparison tables) belong to that failure; fold them into its
        # message until the streak breaks. Harness chatter ("Looks like you
        # failed ...") and lines that start a new failure end the streak.
        if ( defined $active_err ) {
            if (   $indent == $active_indent
                && $line =~ /^\s*#\s*(.*?)\s*$/
                && $1 !~ /^(?:Subtest:|Failed test\b|$AT_LINE|Looks like\b)/ )
            {
                $active_err->{message} .= "\n$1" if length $1;
                next;
            }
            $active_err = undef;
        }

        if ( $line =~ /^\s*#\s*Subtest:\s*(.+?)\s*$/ ) {
            open_subtest( \@stack, $1, $indent );
            next;
        }

        if ( $brace_open->{$i} && $line =~ /$OK_LINE(.*?)\s*\{\s*$/ ) {
            my $failed = defined $1;
            my ( $name, $directive ) = split_desc($2);
            open_subtest( \@stack, $name, $indent,
                brace => 1, status => tap_status( $directive, $failed ) );
            next;
        }

        if ( $brace_close->{$i} && $line =~ /^\s*\}\s*$/ ) {
            if (   @stack
                && $stack[-1]{brace}
                && $indent == $stack[-1]{marker_indent} )
            {
                close_subtest( $file, \@stack, $stack[-1]{status} );
            }
            next;
        }

        if (   @stack
            && $stack[-1]{brace}
            && $indent == $stack[-1]{content_indent}
            && $line =~ /^\s*1\.\.0\s*#\s*SKIP\b/i )
        {
            $stack[-1]{status} = 'skipped';
            next;
        }

        if ( $line =~ /$OK_LINE(.*)$/ ) {
            my $failed = defined $1;
            my ( $desc, $directive ) = split_desc($2);
            if (   @stack
                && !$stack[-1]{brace}
                && $indent == $stack[-1]{marker_indent}
                && $desc eq $stack[-1]{name} )
            {
                close_subtest( $file, \@stack, tap_status( $directive, $failed ) );
            }
            next;
        }

        if ( $line =~ /^\s*#\s*Failed test\b(.*)$/ ) {
            ( my $msg = "Failed test$1" ) =~ s/\s+$//;

            # Test::More collapses "Failed test" and "at FILE line N" onto
            # one line when the assertion has no description (e.g. `ok(0)`,
            # `is($a, $b)`); no separate "at" line follows, so record the
            # error now instead of parking a pending message.
            if ( $msg =~ /^Failed test\s+$AT_LINE\.?$/ ) {
                my ( $lineno, $where ) = error_location( $test_path, $1, $2 );
                $active_err = add_error( $file, \@stack, $indent,
                    join( "\n", 'Failed test', $where ? $where : () ), $lineno );
                $active_indent = $indent;
            }
            else {
                $pending_msg{$indent} = $msg;
            }
            next;
        }

        if ( $line =~ /^\s*#\s*$AT_LINE/ ) {
            my ( $lineno, $where ) = error_location( $test_path, $1, $2 );
            my $msg = delete $pending_msg{$indent};
            $msg = 'Test failed' unless defined $msg;
            $active_err = add_error( $file, \@stack, $indent,
                join( "\n", $msg, $where ? $where : () ), $lineno );
            $active_indent = $indent;
            next;
        }
    }
}

# Push a newly opened subtest onto the stack. Its body is expected 4 spaces
# deeper than the line that opened it. `%extra` carries the Test2 brace-style
# specifics (`brace`, `status`), which the Test::More form does not have.
sub open_subtest {
    my ( $stack, $name, $indent, %extra ) = @_;
    my @names = map { $_->{name} } @$stack;
    push @names, $name;
    push @$stack,
      {
        name           => $name,
        marker_indent  => $indent,
        content_indent => $indent + 4,
        names          => \@names,
        errors         => [],
        %extra,
      };
    return;
}

# Pop the innermost subtest and record it under its `::`-joined name path.
sub close_subtest {
    my ( $file, $stack, $status ) = @_;
    my $st = pop @$stack;
    $file->{subtests}{ join '::', @{ $st->{names} } } = {
        status => $status,
        errors => $st->{errors},
    };
    return;
}

# Determine which "(not )?ok ... {" lines are genuine Test2::V0 subtest
# openers, by pairing them with a later bare "}" at the same indent. Any
# candidate that reaches end-of-file unmatched -- e.g. a plain assertion
# whose description happens to end in a literal "{" -- is left unmatched so
# `parse_subtests` treats it as an ordinary ok/not-ok line instead.
sub find_brace_pairs {
    my ($lines) = @_;
    my ( %is_open, %is_close );
    my @stack;    # candidate opens: { indent => ..., idx => ... }

    for my $i ( 0 .. $#$lines ) {
        my $line = $lines->[$i];
        my ($ws) = $line =~ /^(\s*)/;
        my $indent = length $ws;

        if ( $line =~ /$OK_LINE.*?\{\s*$/ ) {
            push @stack, { indent => $indent, idx => $i };
            next;
        }

        if ( $line =~ /^\s*\}\s*$/ ) {
            # Discard candidates opened deeper than this closer -- they were
            # never legitimately closed, so they weren't real openers.
            pop @stack while @stack && $stack[-1]{indent} > $indent;
            if ( @stack && $stack[-1]{indent} == $indent ) {
                my $open = pop @stack;
                $is_open{ $open->{idx} } = 1;
                $is_close{$i}            = 1;
            }
            next;
        }
    }
    return ( \%is_open, \%is_close );
}

# Split the payload of a TAP ok-line into its description and its directive
# comment. Only an *unescaped* `#` starts a directive: Test::More and Test2
# both escape `#` and `\` inside a description, so a subtest named
# "has # hash" is emitted as `ok 1 - has \# hash`. Cutting at the first `#`
# instead would leave a description that never matches the name recorded from
# the `# Subtest:` line, so the subtest would never be closed and every
# subtest after it would be recorded as its child.
sub split_desc {
    my ($rest) = @_;
    my ( $desc, $directive ) = ( $rest, '' );
    if ( $rest =~ /^((?:\\.|[^\\#])*)(#.*)$/s ) {
        ( $desc, $directive ) = ( $1, $2 );
    }
    $desc =~ s/^\s+//;
    $desc =~ s/\s+$//;
    $desc =~ s/\\(.)/$1/g;
    return ( $desc, $directive );
}

# Map a TAP ok-line's directive/failure state to a subtest status.
sub tap_status {
    my ( $directive, $failed ) = @_;
    return
        $directive =~ /^#\s*skip/i ? 'skipped'
      : $failed                    ? 'failed'
      :                              'passed';
}

# Resolve a TAP "at FILE line N" location against the test file being parsed.
# Test::More reports the location of the assertion itself, which for an
# assertion made inside a helper module is a different file -- attaching its
# line number to the test file would drop a diagnostic on an unrelated line,
# so a foreign location is returned as trailing message text instead.
# Returns (line, extra message text); exactly one of the two is set.
sub error_location {
    my ( $test_path, $at_file, $at_line ) = @_;
    ( my $reported = $at_file ) =~ s{^\./}{};
    return ( $at_line, '' )
      if $test_path eq $reported || $test_path =~ m{/\Q$reported\E$};
    return ( undef, "at $at_file line $at_line" );
}

# Attach an error to the subtest whose body sits at the given indent, or to
# the file when no such subtest is open. Returns the error so the caller can
# keep appending follow-up diagnostic lines to its message.
sub add_error {
    my ( $file, $stack, $indent, $msg, $lineno ) = @_;
    my $err = { message => $msg, line => defined $lineno ? $lineno + 0 : undef };
    for my $st (@$stack) {
        if ( $st->{content_indent} == $indent ) {
            push @{ $st->{errors} }, $err;
            return $err;
        }
    }
    push @{ $file->{errors} }, $err;
    return $err;
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

# `line` is null for a failure whose reported location is not in this test
# file; the Lua side leaves such an error unanchored rather than pinning it to
# an arbitrary line.
sub encode_errors {
    my ($errors) = @_;
    return '['
      . join( ',',
        map {
                '{"message":'
              . json_str( $_->{message} )
              . ',"line":'
              . ( defined $_->{line} ? $_->{line} + 0 : 'null' ) . '}'
        } @$errors )
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
