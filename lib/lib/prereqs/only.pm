package lib::prereqs::only;

# DATE
# VERSION

use strict;
use warnings;

require lib::filter;

sub import {
    my ($pkg, %opts) = @_;

    my $allow_runtime_requires   = delete $opts{RuntimeRequires}   // 1;
    my $allow_runtime_recommends = delete $opts{RuntimeRecommends} // 0;
    my $allow_runtime_suggests   = delete $opts{RuntimeSuggests}   // 0;
    my $allow_test_requires      = delete $opts{TestRequires}      // 1;
    my $allow_test_recommends    = delete $opts{TestRecommends}    // 0;
    my $allow_test_suggests      = delete $opts{TestSuggests}      // 0;
    my $allow_core               = delete $opts{allow_core}        // 0;
    my $debug                    = delete $opts{debug}             // 0;
    my $allow                    = delete $opts{allow};
    my $disallow                 = delete $opts{disallow};
    for (keys %opts) {
        die "Unknown options '$_', see documentation for known options";
    }
    my $dbgh = "[lib::prereqs::only]";

    #print "D:ENV:\n", map {"  $_=$ENV{$_}\n"} sort keys %ENV;
    my $running_under_prove = do {
        ($ENV{_} // '') =~ m![/\\]prove\z! ? 1:0;
    };
    warn "$dbgh we are running under prove\n" if $running_under_prove && $debug;

    my %allow;
    my @allow_re;
    my @disallow;

    unless ($allow_core) {
        # these are modules required by lib::filter itself, so they are already
        # loaded. we need to disallow them explicitly.
        push @disallow, (
            "strict", "warnings", "warnings::register",
            "Config", "vars",
            "lib::filter",
        );
    }
    if ($running_under_prove) {
        # modules required by prove
        $allow{$_} = 1 for qw(
                                 App::Prove
                                 TAP::Harness TAP::Harness::Env
                                 constant
                                 TAP::Object
                                 Text::ParseWords
                                 Exporter
                                 File::Spec
                                 File::Path
                                 IO::Handle
                                 Symbol
                                 SelectSaver
                                 IO
                                 TAP::Formatter::Console
                                 TAP::Formatter::Base
                                 POSIX
                                 Fcntl
                                 Tie::Hash
                                 TAP::Formatter::Color
                                 TAP::Parser::Aggregator
                                 Benchmark
                                 TAP::Parser::Scheduler
                                 TAP::Parser::Scheduler::Job
                                 TAP::Parser::Scheduler::Spinner
                                 TAP::Parser
                                 TAP::Parser::Grammar
                                 TAP::Parser::ResultFactory
                         );
        push @allow_re, '^File::Spec::';
    }

    {
        open my($fh), "<", "dist.ini"
            or die "Can't open dist.ini in current directory: $!";
        my $cur_section = '';
        my ($key, $value);
        while (defined(my $line = <$fh>)) {
            chomp $line;
            #print "D:line=<$line>\n";
            if ($line =~ /\A\s*\[\s*([^\]]+?)\s*\]\s*\z/) {
                #print "D:section=<$1>\n";
                $cur_section = $1;
                next;
            } elsif ($line =~ /\A\s*([^;][^=]*?)\s*=\s*(.*?)\s*\z/) {
                ($key, $value) = ($1, $2);
                next if $key eq 'perl';
                if ($cur_section =~ m!\A(Prereqs|Prereqs\s*/\s*RuntimeRequires)\z! && $allow_runtime_requires) {
                    $allow{$key} = 1;
                } elsif ($cur_section =~ m!\A(Prereqs\s*/\s*RuntimeRecommends)\z!  && $allow_runtime_recommends) {
                    $allow{$key} = 1;
                } elsif ($cur_section =~ m!\A(Prereqs\s*/\s*RuntimeSuggests)\z!    && $allow_runtime_suggests) {
                    $allow{$key} = 1;
                } elsif ($cur_section =~ m!\A(Prereqs\s*/\s*TestRequires)\z!       && $allow_test_requires) {
                    $allow{$key} = 1;
                } elsif ($cur_section =~ m!\A(Prereqs\s*/\s*TestRecommends)\z!     && $allow_test_recommends) {
                    $allow{$key} = 1;
                } elsif ($cur_section =~ m!\A(Prereqs\s*/\s*TestSuggests)\z!       && $allow_test_suggests) {
                    $allow{$key} = 1;
                }
            }
        }
        warn "$dbgh modules collected from prereqs in dist.ini: ", join(";", sort keys %allow), "\n"
            if $debug;
    }

    # collect modules under lib/
    {
        my @distmods;
        my $code_find_pm;
        $code_find_pm = sub {
            my ($dir, $fulldir) = @_;
            chdir $dir or die "Can't chdir to '$fulldir': $!";
            opendir my($dh), "." or die "Can't opendir '$fulldir': $!";
            for my $e (readdir $dh) {
                next if $e eq '.' || $e eq '..';
                if (-d $e) {
                    $code_find_pm->($e, "$fulldir/$e");
                }
                next unless $e =~ /\.pm\z/;
                my $mod = "$fulldir/$e"; $mod =~ s/\.pm\z//; $mod =~ s!\Alib/!!; $mod =~ s!/!::!g;
                push @distmods, $mod;
                $allow{$mod} = 1;
            }
            chdir ".." or die "Can't chdir back to '$fulldir': $!";
        };
        $code_find_pm->("lib", "lib");
        warn "$dbgh modules under lib/: ", join(";", @distmods), "\n"
            if $debug;
    }

    # allow
    if (defined $allow) {
        $allow{$_} = 1 for split /;/, $allow;
    }

    lib::filter->import(
        allow_core    => $allow_core,
        allow_noncore => 0,
        debug         => $debug,
        disallow      => join(';', @disallow,
                              (defined $disallow ? split(/;/, $disallow) : ())),
        allow         => join(';', sort keys %allow),
        (allow_re     => join("|", @allow_re)) x !!@allow_re,
    );
}

sub unimport {
    lib::filter->unimport;
}

1;
# ABSTRACT: Only allow modules specified in prereqs in dist.ini to be locateable/loadable

=for Pod::Coverage .+

=head1 SYNOPSIS

 % cd perl-Your-Dist
 % PERL5OPT=-Mlib::prereqs::only prove -l


=head1 DESCRIPTION

This pragma reads the prerequisites found in F<dist.ini>, the modules found in
F<lib/>, and uses L<lib::filter> to only allow those modules to be
locateable/loadable. It is useful while testing L<Dist::Zilla>-based
distribution: it tests that the prerequisites you specify in F<dist.ini> is
already complete (at least to run the test suite).

By default, only prereqs specified in RuntimeRequires and TestRequires sections
are allowed. But you can include other sections too if you want:

 % PERL5OPT=-Mlib::prereqs::only=RuntimeRecommends,1,TestSuggests,1 prove ...

Currently only (Runtime|Test)(Requires|Recommends|Suggests) are recognized.

Other options that can be passed to the pragma:

=over

=item * allow_core => bool (default: 0)

This will be passed to lib::filter. If you don't specify core modules in your
prereqs, you'll want to set this to 1.

=item * debug => bool (default: 0)

If set to 1, will print debug messages.

=item * allow => str

Specify an extra set of modules to allow. Value is a semicolon-separated list of
module names.

=item * disallow => str

Specify an extra set of modules to disallow. Value is a semicolon-separated list
of module names.

=back


=head1 SEE ALSO

L<lib::filter>

=cut
