package Class::Veyra::SourceCollector;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Parser;
use Class::Veyra::SourceLoader;

sub new {
    my ($class, %args) = @_;

    my $loader = Class::Veyra::SourceLoader->new(%args);

    return bless {
        loader => $loader,
    }, $class;
}

sub collect {
    my ($self, $entry_name) = @_;

    my @sources;
    my %seen;

    $self->_visit(
        $entry_name,
        \@sources,
        \%seen,
    );

    return \@sources;
}

sub _visit {
    my ($self, $name, $sources, $seen) = @_;

    my $path = $self->{loader}->resolve($name);

    if (exists $seen->{$path}) {
        $self->_require_declaration(
            $name,
            $path,
            $seen->{$path},
        );

        return;
    }

    my $source = $self->{loader}->load($name);

    my $document = eval {
        Class::Veyra::Parser->parse(
            $source->{source},
            $source->{source_name},
        );
    };

    my $error = $@;

    die "Cannot parse Veyra source '$path': $error"
        unless defined $document;

    $self->_require_declaration(
        $name,
        $path,
        $document,
    );

    $seen->{$path} = $document;

    push @$sources, $source;

    for my $import (@{ $document->{imports} }) {
        my $completed = eval {
            $self->_visit(
                $import->{name},
                $sources,
                $seen,
            );

            1;
        };

        my $import_error = $@;

        die "Import '$import->{name}' in '$path' "
            . "at offset $import->{offset}: $import_error"
            unless $completed;
    }

    return;
}

sub _require_declaration {
    my ($self, $name, $path, $document) = @_;

    for my $declaration (@{ $document->{declarations} }) {
        return if $declaration->{name} eq $name;
    }

    die "Veyra source '$path' requested as '$name' "
        . "does not declare '$name'\n";
}

1;
