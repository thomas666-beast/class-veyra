package Class::Veyra::Compiler;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Parser;
use Class::Veyra::SyntaxGuard;
use Class::Veyra::Contract;
use Class::Veyra::InterfaceCheck;
use Class::Veyra::ReferenceCheck;
use Class::Veyra::Generator;
use Class::Veyra::SourceCollector;
use Class::Veyra::MethodCheck;
use Class::Veyra::ConstructorCheck;

sub analyze {
    my ($class, $source, $source_name) = @_;

    _validate_source($source);

    my $document =
        Class::Veyra::Parser->parse(
            $source,
            $source_name,
        );

    return _validate_document($document);
}

sub analyze_sources {
    my ($class, $sources) = @_;

    die "Compiler sources must be an array reference\n"
        unless ref $sources eq 'ARRAY';

    my @documents;
    my @classes;
    my @interfaces;
    my @declarations;

    my %seen_sources;
    my %seen_declarations;

    for my $entry (@$sources) {
        die "Each compiler source must be a hash reference\n"
            unless ref $entry eq 'HASH';

        my $source_name = $entry->{source_name};

        die "Each compiler source requires a non-empty source_name\n"
            if !defined $source_name
                || ref $source_name
                || $source_name eq '';

        die "Duplicate source name '$source_name'\n"
            if $seen_sources{$source_name}++;

        _validate_source($entry->{source});

        my $document =
            Class::Veyra::Parser->parse(
                $entry->{source},
                $source_name,
            );

        for my $node (@{ $document->{declarations} }) {
            my $name = $node->{name};

            if (exists $seen_declarations{$name}) {
                my $previous = $seen_declarations{$name};

                die "Duplicate declaration '$name': "
                    . "$previous->{kind} in "
                    . "'$previous->{source_name}' conflicts with "
                    . "$node->{kind} in '$source_name'\n";
            }

            $seen_declarations{$name} = $node;
        }

        push @documents, $document;
        push @classes, @{ $document->{classes} };
        push @interfaces, @{ $document->{interfaces} };
        push @declarations, @{ $document->{declarations} };
    }

    my $project = {
        kind         => 'document',
        source_name  => '<project>',
        sources      => \@documents,
        classes      => \@classes,
        interfaces   => \@interfaces,
        declarations => \@declarations,
    };

    my $validated = _validate_document($project);

    Class::Veyra::ReferenceCheck->validate($validated);
    Class::Veyra::ConstructorCheck->validate($validated);
    Class::Veyra::MethodCheck->validate($validated);

    return $validated;
}

sub analyze_module {
    my ($class, $entry_name, %options) = @_;

    my $collector = Class::Veyra::SourceCollector->new(
        %options,
    );

    my $sources = $collector->collect($entry_name);

    return $class->analyze_sources($sources);
}

sub compile {
    my ($class, $source, $source_name) = @_;

    my $document = $class->analyze(
        $source,
        $source_name,
    );

    return Class::Veyra::Generator->generate($document);
}

sub compile_sources {
    my ($class, $sources) = @_;

    my $document = $class->analyze_sources($sources);

    return Class::Veyra::Generator->generate($document);
}

sub compile_module {
    my ($class, $entry_name, %options) = @_;

    my $document = $class->analyze_module(
        $entry_name,
        %options,
    );

    return Class::Veyra::Generator->generate($document);
}

sub compile_file {
    my ($class, $input_path, $output_path) = @_;

    require Class::Veyra::FileCompiler;

    return Class::Veyra::FileCompiler->compile_file(
        $input_path,
        $output_path,
    );
}

sub _validate_source {
    my ($source) = @_;

    die "Compiler requires a defined source string\n"
        unless defined $source;

    die "Compiler source must not be a reference\n"
        if ref $source;

    return;
}

sub _validate_document {
    my ($document) = @_;

    Class::Veyra::SyntaxGuard->validate($document);

    Class::Veyra::Contract->validate($document);

    Class::Veyra::InterfaceCheck->validate($document);

    return $document;
}

1;
