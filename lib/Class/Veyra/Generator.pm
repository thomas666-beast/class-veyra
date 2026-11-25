package Class::Veyra::Generator;

use v5.38;
use strict;
use warnings;

sub generate {
    my ($class, $document) = @_;

    my @output = (
        "use v5.38;\n",
        "use strict;\n",
        "use warnings;\n",
        "use feature 'class';\n",
        "no warnings 'experimental::class';\n\n",
    );

    for my $interface (@{ $document->{interfaces} }) {
        push @output,
            "# interface $interface->{name}: "
            . "validated at compile time; "
            . "no runtime representation\n";
    }

    push @output, "\n"
        if @{ $document->{interfaces} };

    my $classes = _ordered_classes($document->{classes});

    for my $node (@$classes) {
        my $name = $node->{name};

        my $declaration = "class $name";

        if (defined $node->{parent}) {
            $declaration .= " :isa($node->{parent})";
        }

        push @output, "$declaration {\n";

        for my $member (@{ $node->{members} }) {
            if ($member->{kind} eq 'use') {
                push @output, "    use $member->{name} ();\n";
                next;
            }

            if ($member->{kind} eq 'field') {
                my $field_declaration =
                    '    field $' . $member->{name};

                $field_declaration .= ' :param'
                    if $member->{parameter};

                push @output, "$field_declaration;\n";

                next;
            }

            my $kind = $member->{kind};

            die "Class '$name': unsupported member kind '$kind'\n"
                unless $kind eq 'fun' || $kind eq 'act';

            my $operation_name = $member->{name};

            die "Class '$name': operation name 'new' is reserved\n"
                if $operation_name eq 'new';

            my $signature = join ', ', map {
                '$' . $_->{name}
            } @{ $member->{parameters} };

            push @output,
                "\n    method $operation_name ($signature) {\n";

            if ($kind eq 'fun') {
                push @output,
                    "        return scalar((sub {\n",
                    $member->{body},
                    "\n        })->());\n";
            }
            else {
                push @output,
                    "        (sub {\n",
                    $member->{body},
                    "\n        })->();\n",
                    "        return;\n";
            }

            push @output, "    }\n";
        }

        push @output, "}\n\n";
    }

    push @output, "1;\n";

    return join '', @output;
}

sub _ordered_classes {
    my ($classes) = @_;

    my @pending = @$classes;
    my @ordered;
    my %emitted;

    while (@pending) {
        my @remaining;
        my $progress = 0;

        for my $node (@pending) {
            my $parent = $node->{parent};

            if (defined $parent && !$emitted{$parent}) {
                push @remaining, $node;
                next;
            }

            push @ordered, $node;

            $emitted{ $node->{name} } = 1;
            $progress = 1;
        }

        die "Generator cannot order classes: "
            . "unresolved parent or inheritance cycle\n"
            unless $progress;

        @pending = @remaining;
    }

    return \@ordered;
}

1;
