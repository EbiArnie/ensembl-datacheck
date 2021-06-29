=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the 'License');
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an 'AS IS' BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::EnsEMBL::DataCheck::Checks::ChromosomesAnnotated;

use warnings;
use strict;

use Moose;
use Test::More;
use Bio::EnsEMBL::DataCheck::Utils qw/sql_count/;

extends 'Bio::EnsEMBL::DataCheck::DbCheck';

use constant {
  NAME           => 'ChromosomesAnnotated',
  DESCRIPTION    => 'Chromosomal seq_regions have appropriate attribute',
  GROUPS         => ['assembly', 'core', 'brc4_core'],
  DB_TYPES       => ['core'],
  TABLES         => ['attrib_type', 'coord_system', 'seq_region', 'seq_region_attrib']
};

sub skip_tests {
  my ($self) = @_;

  my $sa = $self->dba->get_adaptor('Slice');

  my $mca = $self->dba->get_adaptor('MetaContainer');
  my $cs_version = $mca->single_value_by_key('assembly.default');

  my @chromosomal = ('chromosome', 'chromosome_group', 'plasmid');

  my $chr_count = 0;
  foreach my $cs_name (@chromosomal) {
    my $slices = $sa->fetch_all($cs_name, $cs_version);
    foreach (@$slices) {
      # seq_regions that are not genuine biological chromosomes,
      # but are instead collections of unmapped sequence,
      # have a 'chromosome' attribute - these regions do not
      # necessarily need a karyotype_rank attribute.
      my @non_bio_chr = @{$_->get_all_Attributes('chromosome')};
      if (! scalar(@non_bio_chr)) {
        $chr_count++;
      }
    }
  }

  if ( $chr_count <= 1 ) {
    return (1, 'Zero or one chromosomal seq_regions.');
  }
}

sub tests {
  my ($self) = @_;

  my $sa = $self->dba->get_adaptor('Slice');

  my $mca = $self->dba->get_adaptor('MetaContainer');
  my $cs_version = $mca->single_value_by_key('assembly.default');

  my @chromosomal = ('chromosome', 'chromosome_group', 'plasmid');

  foreach my $cs_name (@chromosomal) {
    my $slices = $sa->fetch_all($cs_name, $cs_version);
    foreach (@$slices) {
      my @non_bio_chr = @{$_->get_all_Attributes('chromosome')};
      next if scalar(@non_bio_chr);

      my $sr_name = $_->seq_region_name;
      my $desc = "$cs_name $sr_name has 'karyotype_rank' attribute";
      ok($_->has_karyotype, $desc);
      
      my $desc2 = "$cs_name $sr_name should have only one 'karyotype_rank' attribute";
      my $diag2 = "There is more than 1 'karyotype_rank' per seq_region_id";
      my $srid = $_->get_seq_region_id;
      my $sql = "
        select seq_region_id
        from
          seq_region_attrib sra,
          attrib_type at
        where
          at.attrib_type_id=sra.attrib_type_id and
          at.code='karyotype_rank' and
          sra.seq_region_id=$srid
        group by
          sra.seq_region_id
        having count(seq_region_id) > 1;
      ";

      is_rows_zero(
        $self->dba,
        $sql,
        $desc2,
        $diag2
      );

      if ($sr_name =~ /^(chrM|chrMT|MT|Mito|mitochondrion_genome)$/) {
        my $desc_mt = "$cs_name $sr_name has mitochondrial 'sequence_location' attribute";
        my %seq_locs = map { $_->value => 1 } @{$_->get_all_Attributes('sequence_location')};
        ok(exists $seq_locs{'mitochondrial_chromosome'}, $desc_mt);
      }
    }
  }
}

1;
