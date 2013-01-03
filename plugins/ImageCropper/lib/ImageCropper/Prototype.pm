# This code is licensed under the GPLv2
# Copyright (C) 2009 Endevver LLC.

package ImageCropper::Prototype;

use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties( {
        column_defs => {
            'id'           => 'integer not null auto_increment',
            'blog_id'      => 'integer not null',
            'label'        => 'string(100) not null',
            'default_tags' => 'string(255)',
            'max_width'    => 'smallint not null',
            'max_height'   => 'smallint not null',
            'compression'  => 'string(30)',
        },
        audit   => 1,
        indexes => {
            blog_id => 1,
            labels  => { columns => [ 'blog_id', 'label' ], },
        },
        datasource  => 'crop',
        primary_key => 'id',
    }
);

sub class_label {
    MT->translate("Thumbnail Prototype");
}

sub class_label_plural {
    MT->translate("Thumbnail Prototypes");
}

# The MT5 listing screen
sub listing_screen {
    return {
        primary => 'created_on',
        default_sort_key => 'created_on',
        screen_label => 'Thumbnail Prototypes Test!',
    };
}

sub list_properties {
    return {
        id => {
            auto    => 1,
            label   => 'ID',
            order   => 100,
            display => 'optional',
        },
        label => {
            base    => '__virtual.string',
            col     => 'label',
            label   => 'Label',
            order   => 200,
            display => 'default',
            html => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $uri = $app->uri . '?__mode=edit_prototype&id=' . $obj->id
                    . '&blog_id=' . $obj->blog_id;
                return '<a href="javascript:void(0)"'
                    . 'onclick="jQuery.fn.mtDialog.open(\''
                    . $uri . '\')">' . $obj->label . '</a>';
            },
        },
        max_width => {
            auto    => 1,
            label   => 'Max Width',
            order   => 300,
            display => 'default',
        },
        max_height => {
            auto    => 1,
            label   => 'Max Height',
            order   => 400,
            display => 'default',
        },
        created_by => {
            base  => '__virtual.author_name',
            order => 500,
            display => 'default',
        },
        created_on => {
            base    => '__virtual.created_on',
            order   => 600,
            display => 'default',
        },
    };
}

1;
__END__
