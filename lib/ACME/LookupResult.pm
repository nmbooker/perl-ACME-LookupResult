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

=head2 LIMITATIONS

Mostly stability.  I'm not completely sure what precise interface I'm going
to expose to constructors or clients.  This is reflected in my initial choice of
the ACME namespace.

I'm not sure how to, or whether to, communicate via enforcement whether undef
is a valid looked up value and therefore somehow force the caller to check
for success with e.g. C<Found> or C<NotFound> (or whatever aliases I may come
up with like C<< $lookup->Succeeded >>), effectively disabling the C<OrUndef> option.  C<Slip> would continue to work because you can tell the difference with
that between existance of undef C<(undef)> and nothing C<()> but it doesn't
check that the client has checked that way.

=cut

use v5.28;
use strict;
use warnings;

1;
