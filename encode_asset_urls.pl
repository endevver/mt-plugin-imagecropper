#!/usr/local/bin/perl -w

package MT::Tool::ImageCropper;

use strict;
use warnings;
use lib qw( lib extlib plugins/ImageCropper/lib );
use base qw( MT::Tool );
use MT;
use MT::Asset;
use MT::Util qw( encode_url );

sub main {
    my $app = MT->instance;
    my $counter = 0;

    my $blog_id = $ARGV[0];

    my $terms = {
        class  => ['image', 'photo'],
    };

    if ($blog_id) {
        $terms->{blog_id} = $blog_id;
    }

    my $iter = $app->model('asset')->load_iter(
        $terms,
        {
            sort      => 'blog_id',
            direction => 'ascend',
        }
    );

    while ( my $asset = $iter->() ) {
        my $file_name = $asset->file_name;
        my $enc_file_name = encode_url( $file_name );

        my $url = $asset->url;

        next if $url =~ m/$enc_file_name/;

        print "* Found asset " . $asset->id . ',  in blog ID ' . $asset->blog_id
            . ': ' . $asset->file_name . "\n";
        print "  * Original URL: $url\n";

        $url =~ s!(.)$file_name$!$1!;
        $url .= $enc_file_name;

        $asset->url( $url );
        # $asset->save or die $asset->errstr;

        print '  * Updated URL: ' . $asset->url . "\n\n";
        $counter++;
    }

    print "Updated $counter assets.\n";
}

__PACKAGE__->main();
