use utf8;
package Opencloset::Schema::Result::Order;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Opencloset::Schema::Result::Order

=cut

use strict;
use warnings;

=head1 BASE CLASS: L<Opencloset::Schema::Base>

=cut

use base 'Opencloset::Schema::Base';

=head1 TABLE: C<order>

=cut

__PACKAGE__->table("order");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 guest_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 status_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 rental_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1

=head2 target_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1

=head2 return_date

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  inflate_datetime: 1
  is_nullable: 1

=head2 return_method

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 payment_method

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 price

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 discount

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 late_fee

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 l_discount

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 l_payment_method

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 staff_name

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 comment

  data_type: 'text'
  is_nullable: 1

=head2 purpose

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 age

  data_type: 'integer'
  is_nullable: 1

=head2 chest

  data_type: 'integer'
  is_nullable: 1

=head2 waist

  data_type: 'integer'
  is_nullable: 1

=head2 arm

  data_type: 'integer'
  is_nullable: 1

=head2 length

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "guest_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "status_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "rental_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime => 1,
    is_nullable => 1,
  },
  "target_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime => 1,
    is_nullable => 1,
  },
  "return_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    inflate_datetime => 1,
    is_nullable => 1,
  },
  "return_method",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "payment_method",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "price",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "discount",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "late_fee",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "l_discount",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "l_payment_method",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "staff_name",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "comment",
  { data_type => "text", is_nullable => 1 },
  "purpose",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "age",
  { data_type => "integer", is_nullable => 1 },
  "chest",
  { data_type => "integer", is_nullable => 1 },
  "waist",
  { data_type => "integer", is_nullable => 1 },
  "arm",
  { data_type => "integer", is_nullable => 1 },
  "length",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 cloth_orders

Type: has_many

Related object: L<Opencloset::Schema::Result::ClothOrder>

=cut

__PACKAGE__->has_many(
  "cloth_orders",
  "Opencloset::Schema::Result::ClothOrder",
  { "foreign.order_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 guest

Type: belongs_to

Related object: L<Opencloset::Schema::Result::Guest>

=cut

__PACKAGE__->belongs_to(
  "guest",
  "Opencloset::Schema::Result::Guest",
  { id => "guest_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "RESTRICT" },
);

=head2 status

Type: belongs_to

Related object: L<Opencloset::Schema::Result::Status>

=cut

__PACKAGE__->belongs_to(
  "status",
  "Opencloset::Schema::Result::Status",
  { id => "status_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "RESTRICT",
  },
);

=head2 cloths

Type: many_to_many

Composing rels: L</cloth_orders> -> cloth

=cut

__PACKAGE__->many_to_many("cloths", "cloth_orders", "cloth");


# Created by DBIx::Class::Schema::Loader v0.07036 @ 2013-11-12 15:50:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wKsx49K3hi5YfyEosw+PrQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
