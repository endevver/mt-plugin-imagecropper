#!/usr/local/bin/perl -w

use strict;
use v5.16;
use warnings;
use lib qw( lib extlib plugins/ImageCropper/lib );
use MT;
use Media::Type::Simple;
use Try::Tiny;
use Getopt::Long;

my $option = {
    blog_id   => 0,
    extension => undef,
    check     => 0,
    save      => 0,
    version   => 0,
    sort      => 'id',
    direction => 'descend',
    offset    => 0,
};

GetOptions(
    $option,
    'blog_id=i', 'extension=s', 'check', 'save',
    'version', 'sort=s', 'direction=s', 'offset=i',
);

if ( $option->{version} ) {
    say "$0 is using MIME::Types v".$MIME::Types::VERSION;
    exit;
}

my $types          = Media::Type::Simple->new;
$types->add_type( 'video/mp4',          'mp4' );
$types->add_type( 'video/x-m4v',        'm4v' );
$types->add_type( 'video/x-ms-wmv',     'wmv' );
$types->add_type( 'video/quicktime',    'mov' );

my $app            = MT->instance;
my $terms          = { class => '*' };
$terms->{file_ext} = lc($option->{extension}) if $option->{extension};
$terms->{blog_id}  = $option->{blog_id} if $option->{blog_id};

my $args      = {
    sort      => $option->{sort},
    direction => $option->{direction}
};
$args->{offset} = $option->{offset} if $option->{offset};

my $iter    = $app->model('asset')->load_iter( $terms, $args );
while ( my $asset = $iter->() ) {
    my ($type, $mime_col)     = ( '', $asset->mime_type // '' );
    if ( $mime_col ) {
        next unless $option->{check};
        $type = check_type( $asset )
    }
    else {
        ### TODO Should we be looking at $asset->parent?
        $type = find_type( $asset )
    }
    next if ! defined $type;

    if ( $type ne $mime_col ) {
        printf "%-30s %-30s %s\n", $mime_col, $type, $asset->file_name;
        if ( $option->{save} ) {
            $asset->mime_type( $type );
            $asset->save
                or die "Could not save asset: ".($asset->errstr//'Unknown error');
        }
    }
}


sub find_type {
    my $asset = shift;
    my $ext = $asset->file_ext;
    unless ( $ext ) {
        my $fname = $asset->file_name =~ s{\?.*}{}r;
        $ext      = $fname =~ s{.*(\w+)$}{$1}r;
    }
    try { type_from_ext($ext) }
    catch {
        if ( /Unknown extension/ ) {
            say $_;
        }
        else {
            warn $_;
        }
        return undef;
    }
}

# For now, aliased to find_type.
## TODO I was thinking that check_type could actually do more like content sniffing to make sure that the contents match the extension
sub check_type { find_type(@_) }
