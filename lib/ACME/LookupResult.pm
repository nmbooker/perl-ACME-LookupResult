package ACME::LookupResult;
# ABSTRACT: A DSL to flexibly handle success or failure of a lookupo

=head1 DESCRIPTION

Sometimes it's hard to choose what to do when someone calls one of your methods
asking for a specific object and you don't have that object.

Now you don't.  All you need to do is ensure that all non-exceptional branches
in your method return either C<found($object)> or C<not_found()>, document that
that's what you've done and leave it to your client to decide whether it's
fatal and how to check.

The only prereqisite on your client is that they do make a choice to handle
the error by either checking for success (C< Found >), asking for an empty list or undef in the not found case (C<Slip> or C<OrUndef> respectively) or just
asking for (therefore assuming presence of) the C<Value> which will throw an
exception in the C<not_found> case.

=cut

use v5.28;
use strict;
use warnings;

1;
