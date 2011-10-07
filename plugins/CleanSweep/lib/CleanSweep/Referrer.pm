package CleanSweep::Referrer;

use strict;
use warnings;

use MT::Object;
use base qw( MT::Object );

__PACKAGE__->install_properties({
    column_defs => {
        id           => 'integer not null auto_increment', 
        log_id       => 'integer not null', 
        referrer_uri => 'string(255) not null',
        occur        => 'integer not null',
    },
    indexes => {
        referrer_uri => 1,
    },
    audit       => 1,
    datasource  => 'cs_referrer',
    primary_key => 'id',
});

1;
