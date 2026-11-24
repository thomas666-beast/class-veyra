package Class::Veyra::Parser;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;
use Class::Veyra::BodyParser;
use Class::Veyra::InterfaceParser;
use Class::Veyra::QualifiedName;

sub parse {
    my ($class, $source, $source_name) = @_;

    $source_name = '<string>'
        unless defined $source_name;

    die "Parser source name must be a non-empty string\n"
        if ref $source_name || $source_name eq '';

    my $tokens = Class::Veyra::Tokenizer->tokenize($source);

    my $self = bless {
        tokens => $tokens,
        index  => 0,
    }, $class;

    my @classes;
    my @interfaces;
    my @declarations;
    my @imports;
    my %seen;
    my %seen_imports;

    while (my $token = $self->_peek) {
        if (
            $token->{type} eq 'identifier'
            && $token->{text} eq 'import'
        ) {
            $self->_expect('identifier', 'import');

            my $name_token = $self->_read_name;
            my $name = $name_token->{text};

            $self->_expect('symbol', ';');

            die "Duplicate import '$name' "
                . "at offset $name_token->{offset}\n"
                if $seen_imports{$name}++;

            push @imports, {
                kind        => 'import',
                name        => $name,
                source_name => $source_name,
                offset      => $token->{offset},
            };

            next;
        }

        unless (
            $token->{type} eq 'identifier'
            && (
                $token->{text} eq 'class'
                || $token->{text} eq 'interface'
            )
        ) {
            die "Expected 'class' or 'interface' or 'import' "
                . "at offset $token->{offset}, "
                . "found '$token->{text}'\n";
        }

        my $kind = $token->{text};

        $self->_expect('identifier', $kind);

        my $name_token = $self->_read_name;
        my $name = $name_token->{text};

        if (exists $seen{$name}) {
            if ($seen{$name} eq $kind) {
                die "Duplicate $kind '$name' "
                    . "at offset $name_token->{offset}\n";
            }

            die "Declaration name '$name' is already used "
                . "by a $seen{$name} "
                . "at offset $name_token->{offset}\n";
        }

        $seen{$name} = $kind;

        my $parent;

        my $next = $self->_peek;

        if (
            $kind eq 'class'
            && $next
            && $next->{type} eq 'identifier'
            && $next->{text} eq 'extends'
        ) {
            $self->_expect('identifier', 'extends');

            my $parent_token = $self->_read_name;

            $parent = $parent_token->{text};
        }

        my @implements;
        my %seen_interfaces;

        my $following = $self->_peek;

        if (
            $kind eq 'class'
            && $following
            && $following->{type} eq 'identifier'
            && $following->{text} eq 'implements'
        ) {
            $self->_expect('identifier', 'implements');

            while (1) {
                my $interface = $self->_read_name;

                my $interface_name = $interface->{text};

                die "Duplicate implemented interface "
                    . "'$interface_name' in class '$name'\n"
                    if $seen_interfaces{$interface_name}++;

                push @implements, $interface_name;

                my $separator = $self->_peek;

                last unless (
                    $separator
                    && $separator->{type} eq 'symbol'
                    && $separator->{text} eq ','
                );

                $self->_expect('symbol', ',');
            }
        }

        $self->_expect('symbol', '{');

        my $body = $self->_read_body($kind, $name);

        my $node;

        if ($kind eq 'class') {
            my $members = eval {
                Class::Veyra::BodyParser->parse($body);
            };

            my $error = $@;

            die "Class '$name': $error"
                unless defined $members;

            $node = {
                kind       => 'class',
                name       => $name,
                parent     => $parent,
                implements => \@implements,
                body       => $body,
                members    => $members,
                offset     => $token->{offset},
            };

            push @classes, $node;
        }
        else {
            my $closing =
                $tokens->[ $self->{index} - 1 ];

            my $start = $token->{offset};

            my $text = substr(
                $source,
                $start,
                $closing->{offset} + 1 - $start,
            );

            $node =
                Class::Veyra::InterfaceParser->parse($text);

            $node->{offset} += $start;

            for my $requirement (
                @{ $node->{requirements} }
            ) {
                $requirement->{offset} += $start;

                for my $parameter (
                    @{ $requirement->{parameters} }
                ) {
                    $parameter->{offset} += $start;
                }
            }

            push @interfaces, $node;
        }

        $node->{source_name} = $source_name;

        push @declarations, $node;
    }

    return {
        kind         => 'document',
        source_name  => $source_name,
        classes      => \@classes,
        interfaces   => \@interfaces,
        declarations => \@declarations,
        imports      => \@imports,
    };
}

sub _read_name {
    my ($self) = @_;

    my $result = Class::Veyra::QualifiedName->read(
        $self->{tokens},
        $self->{index},
    );

    $self->{index} = $result->{next_index};

    return {
        text   => $result->{name},
        offset => $result->{offset},
    };
}

sub _peek {
    my ($self) = @_;

    my $tokens = $self->{tokens};

    while ($self->{index} < @$tokens) {
        my $token = $tokens->[ $self->{index} ];

        if (
            $token->{type} eq 'whitespace'
            || $token->{type} eq 'comment'
        ) {
            ++$self->{index};
            next;
        }

        return $token;
    }

    return;
}

sub _expect {
    my ($self, $type, $text) = @_;

    my $token = $self->_peek;

    my $expected = defined $text ? "'$text'" : $type;

    die "Expected $expected, found end of source\n"
        unless $token;

    if (
        $token->{type} ne $type
        || (defined $text && $token->{text} ne $text)
    ) {
        die "Expected $expected at offset $token->{offset}, "
            . "found '$token->{text}'\n";
    }

    ++$self->{index};

    return $token;
}

sub _read_body {
    my ($self, $kind, $name) = @_;

    my $tokens = $self->{tokens};
    my @body;
    my $depth = 1;

    while ($self->{index} < @$tokens) {
        my $token = $tokens->[ $self->{index}++ ];

        if ($token->{type} eq 'symbol') {
            if ($token->{text} eq '{') {
                ++$depth;
            }
            elsif ($token->{text} eq '}') {
                --$depth;

                return join('', map { $_->{text} } @body)
                    if $depth == 0;
            }
        }

        push @body, $token;
    }

    die "Unclosed body for $kind '$name'\n";
}

1;
