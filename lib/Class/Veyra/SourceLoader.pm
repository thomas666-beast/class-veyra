package Class::Veyra::SourceLoader;

use v5.38;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Spec;

sub new {
    my ($class, %args) = @_;

    for my $key (sort keys %args) {
        die "Unknown SourceLoader option '$key'\n"
            unless $key eq 'include_paths';
    }

    my $paths = $args{include_paths};

    die "SourceLoader requires a non-empty include_paths array\n"
        unless (
            ref $paths eq 'ARRAY'
            && @$paths
        );

    my @directories;

    for my $path (@$paths) {
        die "SourceLoader include paths must be non-empty strings\n"
            unless (
                defined $path
                && !ref $path
                && length $path
            );

        die "SourceLoader include path '$path' is not a directory\n"
            unless -d $path;

        my $absolute = abs_path($path);

        die "Cannot resolve SourceLoader include path '$path'\n"
            unless defined $absolute;

        push @directories, $absolute;
    }

    return bless {
        include_paths => \@directories,
    }, $class;
}

sub resolve {
    my ($self, $name) = @_;

    die "Invalid Veyra source name\n"
        unless (
            defined $name
            && !ref $name
            && $name =~
                /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/
        );

    my @parts = split /::/, $name;

    $parts[-1] .= '.veyra';

    for my $directory (@{ $self->{include_paths} }) {
        my $candidate = File::Spec->catfile(
            $directory,
            @parts,
        );

        next unless -f $candidate;

        my $absolute = abs_path($candidate);

        die "Cannot resolve Veyra source '$candidate'\n"
            unless defined $absolute;

        return $absolute;
    }

    die "Cannot find Veyra source '$name' in include paths:\n"
        . join(
            '',
            map { "  $_\n" } @{ $self->{include_paths} }
        );
}

sub load {
    my ($self, $name) = @_;

    my $path = $self->resolve($name);

    open my $handle, '<:raw', $path
        or die "Cannot open Veyra source '$path': $!\n";

    my $source;

    {
        local $/;

        $source = readline $handle;

        if (!defined $source) {
            if (eof $handle) {
                $source = '';
            }
            else {
                my $error = "$!";

                close $handle;

                die "Cannot read Veyra source '$path': $error\n";
            }
        }
        elsif (!eof $handle) {
            my $error = "$!";

            close $handle;

            die "Cannot read complete Veyra source '$path': $error\n";
        }
    }

    close $handle
        or die "Cannot close Veyra source '$path': $!\n";

    return {
        source_name => $path,
        source      => $source,
    };
}

1;
