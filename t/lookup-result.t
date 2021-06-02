use Test2::Basic;

use ACME::LookupResult qw<found not_found>;
use Test2::Tools::Compare;

=head1 Introduction

The most general way to return results to users is to always work in terms of lists,
and clients can loop over them.  If there only happens to ever be 1 or 0 objects it's
not a big deal.  But sometimes a single thing being missing is actually a special case
that has to be handled differently - e.g. by showing a 404 instead of an empty page.
With either undef or empty list, handling the empty case is often overlooked.

Ideally, if you don't have what the caller asked for,
you would always return something that quacks the same as what they asked for
but does something sensible for the non-existant case.  This is known as the
Null Object pattern.
But often you can't or the interface would be very hard to construct properly to support
it (or we already have a big slew of client code and there's not time to refactor it so it can support it)

In that case, it is a bind deciding what to do as different calling functions may have different requirements.

The next best thing to a pure list-processing approach or a complete null object
is to allow failure to happen, but to force your caller to handle it somehow so
edge cases don't slip through the net.
This is the approach taken by Rust, Haskell and to a lesser extent Raku, and I think they are right.

Just returning 'undef' or () doesn't do this, but forcing an exception
causes a proliferation of try{..}catch{...} which, especially in Perl5,
is super ugly and makes for very verbose and hard to read code.

Up to now I've ended up writing a lookup function for each failure mode,
which is tedious, and it's hard to keep a consistent naming convention to tell
them apart especially between developers.

The DSL proposed below makes it easy for you to provide a wide choice of error
handling conventions without duplicating lookup code.
The idea is to force the caller to acknowledge the possibility of failure,
while leaving it to them to choose how they handle it, in the absence of
a sensible and complete null object in the failure case.
It lets you represent a failure, bundled along with an error message that can
be used in (at least) developer error messages in the case it was not found so not
every caller has to build its own.

I think this is the least bad way of presenting lookup failures, if lookup failures are what
we must present.

It's designed so a facade/decorator object can augment lookup failures from lower levels
before passing them to their callers, e.g. by specifying a particular exception class,
adding extra contextual information to the error message that the lower level can't know,
converting the error messages into something more human-friendly for things nearer to the GUI,
or providing a null object to be returned with the or_null_object method whose implemntation makes sense within
the subsystem.


So these (contrived) methods:
 $auction->the_lot_named_or_undef("name")
 $auction->the_lot_named_or_die("name")
 $auction->the_lot_named_slip("name")
 $auction->the_lot_named("name")

become:
 $auction->the_lot_named("name")->or_undef
 $auction->the_lot_named("name")->ensure
 $auction->the_lot_named("name")->slip

 $auction->lot_with_name("name")->or_null_object
    # ^ optionally, if provided in the return value of the_lot_named()

You also get to pick up a lookup result, and ask it multiple questions, e.g.:
 my $lookup = $auction->the_lot_named("name");
 $lookup->succeeded;
 $lookup->failed;
 $lookup->error_message;   # that would be the message of the thrown exception
 $lookup->value;   # would throw (preferably croaking) in the case of a failed lookup

I also propose this option:
 my $number_for_display =
     $auction->the_lot_named("name")->match(
         found => sub ($lot) { $lot->number },
         not_found => sub($error) { "[lot not found: $error]" }
         # both subs would be required
     );


All you need to do, at bare minimum, is:
 sub the_lot_named($self, $name)
 {
     my $lot = $self->lots->with_name($name)->single;
     if ($lot)
        { return found($lot) }
     else
        { return not_found() }
 }

Or even:
 sub the_lot_named($self, $name)
 {
     return LookupResult::Factory::from_Maybe($self->lots->with_name($name)->single);
 }

Or for a more useful error message in ->ensure and ->error_message:
 sub the_lot_named($self, $name)
 {
     my $auctname = $self->name;
     return
        LookupResult::Factory::from_Maybe(
            $self->lots->with_name($name)->single
        )
        ->with_error_message(qq[No lot with name "$name" on auction "$auctname"]);
 }

You can also pass these result objects on to other methods, and they themselves
can decide how to handle the nullability of it.


=cut

note "A DSL for handling missing values and, possibly, failure of other types of things (with some renaming or extraction of some parts into a base class)";
note "e.g. was_found, key, or_null_object, with_null_object etc would not live on the base 'Result'";
subtest "Example lookup function using this" => sub
{
    my sub example_lookup_returning_numeric($key)
    {
        my %hash = (existing => 1, existing_2 => 2);
        my $result =
            exists $hashref->{$key}
            # Instead you simply return either found($value) or not_found
            ? found($hashref->{$key})
            : not_found;
        return (
            $result
            ->with_error_message(qq["$key" not found])
                # ^ optionally specialise the error message
            ->with_null_object(0)
                # ^ optionally provide a null value that can be used as a drop-in replacement
                # ^ for a value in the not_found case.  Search "Null object pattern".
                # ^ this should be a better match for your value type than undef
                # ^ this may be a partial implementation as callers can opt out of using it,
                # ^ but a full implementation is better
            # I propose other specialisations we may wish to provide later on,
            # but they are not applied here
        );
    };
    subtest "example: ->slip inside map" => sub
    {
        my $mapped_results = [
            map { example_lookup_returning_numeric($_)->slip }
            qw<existing nonexistant existing_2>
        ];
        is $mapped_results, [1, 2], 'nonexistant keys ignored in map';
    };
    subtest "example: ->or_undef inside map" => sub
    {
        my $mapped_results = [
            map { example_lookup_returning_numeric($_)->or_undef }
            qw<existing nonexistant existing_2>
        ];
        is $mapped_results, [1, undef, 2], 'nonexistant keys undef in map';
    };
    subtest "example: Provide your own alternative to undef inside map" => sub
    {
        my $mapped_results = [
            map { example_lookup_returning_numeric($_)->or_undef // 0 }
            qw<existing nonexistant existing_2>
        ];
        is $mapped_results, [1, 0, 2], 'nonexistant keys 0 in map';

    };
    subtest "Check failed, handle error in if block or value in else block" => sub
    {
        subtest "existing key" => sub
        {
            my $lookup = example_lookup_returning_numeric('existing');
            is $lookup->failed, bool 0, 'not failed';
            is $lookup->value, 1, 'value is 1';
            subtest "example" => sub
            {
                if ($lookup->failed)
                {
                    fail;
                    # Do something with the error, for example log it
                    note 'error: ' . $lookup->error;
                }
                else
                {
                    is $lookup->value, 1;
                    # Do something with the value
                    note 'value: ' . $lookup->value;
                }
            };
        };
        subtest "nonexistant key" => sub
        {
            my $lookup = example_lookup_returning_numeric('nonexistant');
            is $lookup->failed, bool 1, 'failed';
            is $lookup->error, q["nonexistant" not found], q[error is '"nonexistant" not found'];
            ok(dies { $lookup->value }, '->value dies');
            subtest example => sub
            {
                if ($lookup->failed)
                {
                    is $lookup->error, q["nonexistant" not found];
                    # Do something with the error, for example log it
                    note 'error: ' . $lookup->error;
                }
                else
                {
                    fail;
                    # Do something with the value
                    note 'value: ' . $lookup->value;
                }
            };
        };
    };
    subtest "Check succeeded, handle value in if block or error in else block" => sub
    {
        subtest "existing key" => sub
        {
            my $lookup = example_lookup_returning_numeric('existing');
            is $lookup->succeeded, bool 1, 'succeeded';
            is $lookup->value, 1, 'value is 1';
            subtest example => sub
            {
                if ($lookup->succeeded)
                {
                    is $lookup->value, 1;
                    # Do something with the value
                    note '->value: ' . $lookup->value;
                }
                else
                {
                    fail;
                    # Do something with the error, for example log it
                    note '->error: ' . $lookup->error;
                }
            };
        };
        subtest "nonexistant key" => sub
        {
            my $lookup = example_lookup_returning_numeric('nonexistant');
            is $lookup->succeeded, bool 0, 'not succeeded';
            is $lookup->error, q["nonexistant" not found], q[error is '"nonexistant" not found'];
            is $lookup->value, 1, 'value is 1';
            subtest example => sub
            {
                if ($lookup->succeeded)
                {
                    fail;
                    # Do something with the value
                    note '->value: ' . $lookup->value;
                }
                else
                {
                    is $lookup->error, q["nonexistant" not found];
                    # Do something with the error, for example log it
                    note '->error: ' . $lookup->error;
                }
            };
        };
    };
    subtest "Check and assign ->or_undef simultaneously, treat undef as lookup failure, ignore errors" => sub
    {
        note "You can use this approach if undef isn't a valid lookup result";
        note "You can even skip the defined check if you know all valid results will be truthy";
        subtest "existing key" => sub
        {
            is example_lookup_returning_numeric('existing')->or_undef, 1, '->or_undef is 1';
            subtest "example" => sub
            {
                my $outer_variable;
                if (defined(my $number = example_lookup_returning_numeric('existing')->or_undef))
                {
                    # Do something with result
                    $outer_variable = $number;
                }
                is $number_result, 1;
            };
        };
        subtest "nonexistant key" => sub
        {
            is example_lookup_returning_numeric('nonexistant')->or_undef, undef, '->or_undef is undef';
            subtest "example" => sub
            {
                my $outer_variable = 'value which should survive if block';
                if (defined(my $number = example_lookup_returning_numeric('nonexistant')->or_undef))
                {
                    # Do something with result
                    $outer_variable = $number;
                }
                is $outer_variable, 'value which should survive if block';
            };
        };
    };

    subtest "Match possibilities" => sub
    {
        subtest "With both possibilities covered" => sub
        {
            my %possiblities = (
                found => sub($value)
                {
                    return "Succeeded. Value: $value";
                },
                not_found => sub($error_message)
                {
                    return "Failed. Error: $error_message";
                },
            );
            is(
                example_lookup_returning_numeric("existing")->match(%possibilities),
                "Succeeded. Value: 1",
                'existing ->match returns value of "found" coderef',
            );
            is(
                example_lookup_returning_numeric("existing")->match(%possibilities),
                q[Failed. Error: "nonexistant" not found],
                'nonexistant ->match returns value of "not_found" coderef',
            );
        };
        subtest "->match ensures both cases are covered" => sub
        {
            subtest "->match(found => sub{...}) dies if not_found argument missing" => sub
            {
                ok(dies{
                    example_lookup_returning_numeric("existing")->match(found => sub { 'ok' })
                }, 'with key "existing"');
                ok(dies{
                    example_lookup_returning_numeric("nonexistant")->match(found => sub { 'ok' })
                }, 'with nonexistant key');
            };
            subtest "->match(not_found => sub{...}) dies if found argument missing" => sub
            {
                ok(dies{
                    example_lookup_returning_numeric("existing")->match(not_found => sub { 'err' })
                }, 'with key "existing"');
                ok(dies{
                    example_lookup_returning_numeric("nonexistant")->match(not_found => sub { 'err' })
                }, 'with nonexistant key');
            };
        };
    };

    subtest "Look up value in context where missing is an error" => sub
    {
        subtest 'key "existing"' => sub
        {
            is example_lookup_returning_numeric("existing")->ensure, 1, '->ensure returns 1';
        };
        subtest 'nonexistant key' => sub
        {
            ok dies { example_lookup_returning_numeric("nonexistant")->ensure }, '->ensure dies';
            like $@, qr/"nonexistant" not found/,
                'exception message mentions that nonexistant key not found';
        };
    };

    subtest "Accept a provided null object" => sub
    {
        note "In our example, the null object is 0";
        subtest 'key "existing"' => sub
        {
            is(
                example_lookup_returning_numeric("existing")->or_null_object,
                1,
                '->or_null_object returns 1',
            );
        };
        subtest 'nonexistant key' => sub
        {
            is(
                example_lookup_returning_numeric("nonexistant")->or_null_object,
                0,
                '->or_null_object returns 0',
            );
        };
        subtest 'example' => sub
        {
            my $sum;
            {
                $sum = 0;
                for my $key ('existing', 'existing_2', 'nonexistant', 'nonexistant')
                {
                    my $value = example_lookup_returning_numeric($key)->or_null_object;
                    note '$value is ' . $value;
                    $sum += $value;
                }
            }
            is $sum, 3;
            note "\$sum is $sum";
        };
    };
};

subtest "With item found" => sub
{
    my $found_result = found("something");

    is $found_result->succeeded, bool 1, "->succeeded is true";
    is $found_result->was_found, bool 1, "->was_found is true";
    is $found_result->failed, bool 0, "->failed is false";
    is $found_result->value, "something", "->value is something";
    is $found_result->ensure, "something", "->ensure is something";
    my @slip = $found_result->slip;
    is \@slip, ["something"], "->slip is singleton list containing something";
    is [$found_result->or_undef], "something", "->or_undef is something";
    ok(dies { $found_result->error_message }, "->error_message dies");
    subtest "With a null object empty string" => sub
    {
        is(
            found("something")->with_null_object('')->or_null_object,
            "something",
            "->or_null_object is 'something'",
        );
    };
};

subtest "With basic not_found" => sub
{
    my $not_found_result = not_found;

    is not_found->succeeded, bool 0, "->succeeded is false";
    is not_found->was_found, bool 0, "->was_found is false";
    is not_found->failed, bool 1, "->failed is true";
    ok(throws { not_found->value } qr/Not found/, "->value dies, message Not found");
    is not_found->or_undef, undef, "->or_undef is undef";
    my @slip = not_found->slip;
    is \@slip, [], "->slip is empty list";
    is not_found->error_message, "Not found", "->error_message is 'Not found'";
};
subtest "not_found with a custom error" => sub
{
    ok(
        throws { not_found->with_error_message('Custom error')->value }
        qr/Custom error/,
        "->value throws exception with the custom error string"
    );
    ok(
        throws { not_found->with_error_message('Custom error')->ensure }
        qr/Custom error/,
        "->ensure throws exception with the custom error string"
    );
    is(
        not_found->with_error_message('Custom error')->error_message
        'Custom error',
        '->error_message is Custom error'
    );
};

subtest "not_found with a null object empty string" => sub
{
    is(not_found->with_null_object('')->or_null_object, '', "->or_null_object is empty string");
};

subtest "not_found with a custom throw subref" => sub
{
    use failures qw<example>;
    ok(
        throws {
            not_found
                ->with_custom_throw(sub($result) {
                    failure::example->throw({
                        msg => $result->error_message,
                    });
                })
                ->ensure;
        } 'failure::example',
        '->ensure throws a failure::example as specified in the subref'
    );
    # TODO would do nothing to a found()
};

subtest "not_found with transformed error" => sub
{
    note "Useful to transform a lower-level error with extra contextual information";
    my $not_found_result_with_transformed_error =
        not_found
        ->with_error("Key not found")
        ->transform_error(sub($result){
            return $result->error . ": 'foo'";
        });
    is($not_found_result_with_transformed_error->error_message, "Key not found: 'foo'", '->error_message is the transformed error');
    # TODO would do nothing to a found()
};


done_testing;
