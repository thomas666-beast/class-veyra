package Class::Veyra::ProjectFormatter;

use v5.38;
use strict;
use warnings;

use parent 'Class::Veyra::Project';

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempfile);

use Class::Veyra::Compiler;
use Class::Veyra::Formatter;
use Class::Veyra::Generator;
use Class::Veyra::SourceCollector;

sub format {
    my ($self, %options) = @_;

    for my $key (sort keys %options) {
        die "Unknown project formatter option '$key'\n"
            unless $key eq 'check_only'
                || $key eq 'on_change';
    }

    if (exists $options{on_change}) {
        die "Project formatter on_change must be a code reference\n"
            unless ref $options{on_change} eq 'CODE';
    }

    my $root = abs_path($self->{root});

    die "Cannot resolve project root '$self->{root}'\n"
        unless defined $root;

    my $collector = Class::Veyra::SourceCollector->new(
        include_paths => $self->{include_paths},
    );

    my $sources = $collector->collect(
        $self->{entry},
    );

    my @formatted_sources;
    my @changes;

    for my $source (@$sources) {
        my $path = $source->{source_name};

        my $relative = File::Spec->abs2rel(
            $path,
            $root,
        );

        my @parts = File::Spec->splitdir($relative);

        die "Refusing to format source outside project root: '$path'\n"
            if File::Spec->file_name_is_absolute($relative)
            || (@parts && $parts[0] eq File::Spec->updir);

        my $formatted = Class::Veyra::Formatter->format(
            $source->{source},
            $path,
        );

        push @formatted_sources, {
            source_name => $path,
            source      => $formatted,
        };

        next if $formatted eq $source->{source};

        push @changes, {
            path      => $path,
            label     => $relative,
            original  => $source->{source},
            formatted => $formatted,
        };
    }

    my $original_document =
        Class::Veyra::Compiler->analyze_sources(
            $sources,
        );

    my $formatted_document =
        Class::Veyra::Compiler->analyze_sources(
            \@formatted_sources,
        );

    my $original_perl =
        Class::Veyra::Generator->generate(
            $original_document,
        );

    my $formatted_perl =
        Class::Veyra::Generator->generate(
            $formatted_document,
        );

    die "Formatter would change generated Perl tokens; "
        . "no files were modified\n"
        unless Class::Veyra::Formatter->token_fingerprint(
            $original_perl,
        ) eq Class::Veyra::Formatter->token_fingerprint(
            $formatted_perl,
        );

    @changes = sort {
        $a->{label} cmp $b->{label}
    } @changes;

    my @labels = map {
        $_->{label}
    } @changes;

    if (exists $options{on_change}) {
        for my $change (@changes) {
            $options{on_change}->(
                $change->{label},
                $change->{original},
                $change->{formatted},
            );
        }
    }

    return \@labels
        if $options{check_only} || !@changes;

    _replace_sources(\@changes);

    return \@labels;
}

sub _replace_sources {
    my ($changes) = @_;

    my @staged;

    my $completed = eval {
        for my $change (@$changes) {
            my $path = $change->{path};

            die "Refusing to replace symbolic link '$path'\n"
                if -l $path;

            die "Source '$path' is not a regular file\n"
                unless -f $path;

            die "Source '$path' is not writable\n"
                unless -w $path;

            my @status = stat $path;

            die "Cannot inspect source '$path': $!\n"
                unless @status;

            my $mode = $status[2] & 0777;

            my ($handle, $temporary) = tempfile(
                '.veyra-fmt-XXXXXXXX',
                DIR    => dirname($path),
                UNLINK => 0,
            );

            my $staged = {
                %$change,
                handle    => $handle,
                temporary => $temporary,
            };

            push @staged, $staged;

            binmode $handle, ':raw'
                or die "Cannot set formatter output mode: $!\n";

            print {$handle} $change->{formatted}
                or die "Cannot write formatter output: $!\n";

            close $handle
                or die "Cannot close formatter output: $!\n";

            chmod $mode, $temporary
                or die "Cannot preserve source permissions "
                    . "for '$path': $!\n";
        }

        for my $change (@staged) {
            _require_unchanged($change);
        }

        for my $change (@staged) {
            _require_unchanged($change);

            rename $change->{temporary}, $change->{path}
                or die "Cannot replace source "
                    . "'$change->{path}': $!\n";

            delete $change->{temporary};
        }

        1;
    };

    my $error = $@;

    for my $change (@staged) {
        my $handle = $change->{handle};

        close $handle
            if defined fileno $handle;

        unlink $change->{temporary}
            if defined $change->{temporary};
    }

    die $error
        unless $completed;

    return;
}

sub _require_unchanged {
    my ($change) = @_;

    my $path = $change->{path};

    die "Source '$path' became a symbolic link during formatting\n"
        if -l $path;

    die "Source '$path' is no longer a regular file\n"
        unless -f $path;

    my $current = _read_source($path);

    die "Source '$path' changed during formatting; refusing to replace it\n"
        unless $current eq $change->{original};

    return;
}

sub _read_source {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read source '$path': $!\n";

    my $text;

    {
        local $/;

        $text = readline $handle;

        die "Cannot read complete source '$path': $!\n"
            unless eof $handle;
    }

    close $handle
        or die "Cannot close source '$path': $!\n";

    return defined $text ? $text : '';
}

1;
