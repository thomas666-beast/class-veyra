package Class::Veyra::InterfaceCheck;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Inheritance;

sub validate {
    my ($class, $document) = @_;

    my %interfaces = map {
        $_->{name} => $_
    } @{ $document->{interfaces} };

    my %classes = map {
        $_->{name} => $_
    } @{ $document->{classes} };

    my $resolved =
        Class::Veyra::Inheritance->resolve($document);

    my %effective_interfaces;

    for my $class_name (@{ $resolved->{order} }) {
        my $class_node = $classes{$class_name};

        my @required;
        my %seen;

        my $parent = $class_node->{parent};

        if (defined $parent) {
            for my $interface_name (
                @{ $effective_interfaces{$parent} }
            ) {
                next if $seen{$interface_name}++;

                push @required, $interface_name;
            }
        }

        for my $interface_name (
            @{ $class_node->{implements} // [] }
        ) {
            next if $seen{$interface_name}++;

            push @required, $interface_name;
        }

        $effective_interfaces{$class_name} = \@required;

        my $operations =
            $resolved->{operations}{$class_name};

        for my $interface_name (@required) {
            my $interface = $interfaces{$interface_name};

            unless ($interface) {
                if (exists $classes{$interface_name}) {
                    die "Class '$class_name': "
                        . "'$interface_name' is a class, "
                        . "not an interface\n";
                }

                die "Class '$class_name': "
                    . "unknown interface '$interface_name'\n";
            }

            for my $requirement (
                @{ $interface->{requirements} }
            ) {
                my $name = $requirement->{name};
                my $operation = $operations->{$name};

                die "Class '$class_name' implementing "
                    . "'$interface_name': missing "
                    . "$requirement->{kind} '$name'\n"
                    unless $operation;

                if (
                    $operation->{kind}
                    ne $requirement->{kind}
                ) {
                    die "Class '$class_name' implementing "
                        . "'$interface_name': operation '$name' "
                        . "must be $requirement->{kind}, "
                        . "found $operation->{kind}\n";
                }

                my $expected =
                    scalar @{ $requirement->{parameters} };

                my $actual =
                    scalar @{ $operation->{parameters} };

                if ($actual != $expected) {
                    die "Class '$class_name' implementing "
                        . "'$interface_name': operation '$name' "
                        . "requires $expected parameter(s), "
                        . "found $actual\n";
                }
            }
        }
    }

    return 1;
}

1;
