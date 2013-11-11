use utf8;
package Opencloset::Schema::Result::Guest;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Opencloset::Schema::Result::Guest

=cut

use strict;
use warnings;

=head1 BASE CLASS: L<Opencloset::Schema::Base>

=cut

use base 'Opencloset::Schema::Base';

=head1 TABLE: C<guest>

=cut

__PACKAGE__->table("guest");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 chest

  data_type: 'integer'
  is_nullable: 0

=head2 waist

  data_type: 'integer'
  is_nullable: 0

=head2 arm

  data_type: 'integer'
  is_nullable: 1

=head2 length

  data_type: 'integer'
  is_nullable: 1

=head2 height

  data_type: 'integer'
  is_nullable: 1

=head2 weight

  data_type: 'integer'
  is_nullable: 1

=head2 purpose

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 domain

  data_type: 'varchar'
  is_nullable: 1
  size: 64

=head2 create_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1
  set_on_create: 1

=head2 visit_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1
  set_on_create: 1
  set_on_update: 1

=head2 target_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "chest",
  { data_type => "integer", is_nullable => 0 },
  "waist",
  { data_type => "integer", is_nullable => 0 },
  "arm",
  { data_type => "integer", is_nullable => 1 },
  "length",
  { data_type => "integer", is_nullable => 1 },
  "height",
  { data_type => "integer", is_nullable => 1 },
  "weight",
  { data_type => "integer", is_nullable => 1 },
  "purpose",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "domain",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "create_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime => 1,
    is_nullable => 1,
    set_on_create => 1,
  },
  "visit_date",
  {
    data_type                 => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime          => 1,
    is_nullable               => 1,
    set_on_create             => 1,
    set_on_update             => 1,
  },
  "target_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 

Type: belongs_to

Related object: L<Opencloset::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "",
  "Opencloset::Schema::Result::User",
  { id => "id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "RESTRICT" },
);

=head2 orders

Type: has_many

Related object: L<Opencloset::Schema::Result::Order>

=cut

__PACKAGE__->has_many(
  "orders",
  "Opencloset::Schema::Result::Order",
  { "foreign.guest_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 satisfactions

Type: has_many

Related object: L<Opencloset::Schema::Result::Satisfaction>

=cut

__PACKAGE__->has_many(
  "satisfactions",
  "Opencloset::Schema::Result::Satisfaction",
  { "foreign.guest_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-11-11 15:22:59
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MKYbYhTkLWovMNIARJnCUQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
