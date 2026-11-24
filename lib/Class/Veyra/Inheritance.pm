package Class::Veyra::Inheritance;

use v5.38;
use strict;
use warnings;

sub resolve {
    my ($class, $document) = @_;

    my %classes = map {
        $_->{name} => $_
    } @{ $document->{classes} };

    my %interfaces = map {
        $_->{name} => 1
    } @{ $document->{interfaces} };

    my %state;
    my %operations;
    my @order;
    my @path;

    my $visit;

    $visit = sub {
        my ($name) = @_;

        return if ($state{$name} // 0) == 2;

        if (($state{$name} // 0) == 1) {
            die "Inheritance cycle: "
                . join(' -> ', @path, $name)
                . "\n";
        }

        my $node = $classes{$name};

        $state{$name} = 1;
        push @path, $name;

        my %effective;
        my $parent = $node->{parent};

        if (defined $parent) {
            unless (exists $classes{$parent}) {
                if (exists $interfaces{$parent}) {
                    die "Class '$name': parent '$parent' "
                        . "is an interface, not a class\n";
                }

                die "Class '$name': unknown parent '$parent'\n";
            }

            $visit->($parent);

            %effective = %{ $operations{$parent} };
        }

        for my $member (@{ $node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $operation_name = $member->{name};
            my $inherited = $effective{$operation_name};

            if ($inherited) {
                if ($member->{kind} ne $inherited->{kind}) {
                    die "Class '$name': override '$operation_name' "
                        . "must remain $inherited->{kind}, "
                        . "found $member->{kind}\n";
                }

                my $expected =
                    scalar @{ $inherited->{parameters} };

                my $actual =
                    scalar @{ $member->{parameters} };

                if ($actual != $expected) {
                    die "Class '$name': override '$operation_name' "
                        . "requires $expected parameter(s), "
                        . "found $actual\n";
                }
            }

            $effective{$operation_name} = $member;
        }

        $operations{$name} = \%effective;

        pop @path;
        $state{$name} = 2;

        push @order, $name;

        return;
    };

    my $completed = eval {
        for my $node (@{ $document->{classes} }) {
            $visit->($node->{name});
        }

        1;
    };

    my $error = $@;

    undef $visit;

    die $error unless $completed;

    return {
        order      => \@order,
        operations => \%operations,
    };
}

1;
