# $Header: /usr/local/cvsroot/apb/lib/RPM-Make-DWIW/lib/RPM/Make/DWIW.pm,v 1.1 2010-02-22 07:04:21 asher Exp $

package RPM::Make::DWIW;
use strict;

use vars qw( $VERSION );
$VERSION = '0.1';

my $FINAL_RPM_PATH;
my $TOP;

## validation: key => type, mandatory

my $TOP_VAL = {
    tags            => [ {}, 1 ],
    description     => [ '', 1 ],
    items           => [ [], 1],
    requirements    => [ [], 0],
    pre             => [ '', 0 ],
    post            => [ '', 0 ],
    preun           => [ '', 0 ],
    postun          => [ '', 0 ],
    cleanup         => [ '', 0 ],
};

my $TAGS_VAL = {
    Summary         => [ '', 1 ],
    Name            => [ '', 1 ],
    Version         => [ '', 1 ],
    Release         => [ '', 1 ],
    License         => [ '', 1 ],
    Group           => [ '', 1 ],
    Source          => [ '', 0 ],
    URL             => [ '', 0 ],
    Distribution    => [ '', 0 ],
    Vendor          => [ '', 0 ],
    Packager        => [ '', 0 ],
};

my $ITEM_VAL = {
    type            => [ '', 1 ],
    dest            => [ '', 1 ],
    src             => [ '', 0 ],
    mode            => [ '', 1 ],
    owner           => [ '', 1 ],
    group           => [ '', 1 ],
    defaults        => [ '', 0 ],
};

## example spec

my $X = {
    tags => {
        Summary => 'A CD player app that rocks!',
        Name    => 'cdplayer',
        Version => '1.2',
        Release => '3',
        License => 'GPL',
        Group   => 'Applications/Sound',
        #Source => 'ftp://ftp.gnomovision.com/pub/cdplayer/cdplayer-1.0.tgz',
        #URL => 'http://www.gnomovision.com/cdplayer/cdplayer.html',
        #Distribution => 'WSS Linux',
        #Vendor => 'White Socks Software, Inc.',
        #Packager => 'Santa Claus <sclaus@northpole.com>',
    },
    description => 'abc def ghi',
    items => [
        {
            defaults => 1,
            owner    => 'root',
            group    => 'wheel',
            mode     => '0644',
        },
        {
            src   => 'abc.txt',
            dest  => '/home/y/bin/abc.txt',
            mode  => '0755',
            owner => 'yahoo',
            group => 'wheel',
        },
        {
            src   => 'def.txt',
            dest  => '/home/y/lib/def.txt',
        },
        {
            dest  => '/tmp/acme6',
            type  => 'dir',
            mode  => '0777',
        },
    ],
    requirements => [
        {
        name        => 'libxml2',
        min_version => '2.6.0',
        }
    ],
    post => '/sbin/ldconfig',
    cleanup => 0,
};

## mkdir or die

sub xmkdir {
    my $dir = shift;
    mkdir($dir) or die "Can't mkdir $dir: $!";
}

sub mk_dirs {
    $TOP = "topdir-$$";
    system("rm -rf $TOP"); # just in case it exists
    xmkdir($TOP);
    xmkdir("$TOP/RPMS"); # where the rpm will end up
    xmkdir("$TOP/BUILD"); # ??
    xmkdir("$TOP/root"); # where rpmbuild will take files from
}

sub rm_dirs {
    die "top not defined" unless $TOP;
    system("rm -rf $TOP");
}

## generate RPM spec file as string

sub mk_spec {
    my $x = shift;
    my $t = scalar localtime;
    my $res = "## autogenerated by $0 - $t\n\n";
    my $tags = $x->{ tags };
    foreach my $key(sort keys %$tags) {
        $res .= "$key: $tags->{ $key }\n";
    }

    $res .= "\n%description\n$x->{ description }\n\n";

    foreach my $dep(@{ $x->{ requirements } }) {
        my $mv = defined $dep->{ min_ver } ? " >= $dep->{ min_ver }" : '';
        $res .= "requires: $dep->{ name }$mv\n";
    }

    $res .= "\n%files\n";

    my $items = get_items($x);
    foreach my $item(@$items) {
        $res .= mk_spec_file_line($item) . "\n";
    }

    foreach my $section(qw( pre post preun postun )) {
        $res .= "\n\n%$section\n$x->{ $section }\n\n" if $x->{ $section };
    }
    $res;
}

## given file (or dir) hashref, return specfile line

sub mk_spec_file_line {
    my $file = shift;
    foreach my $k(qw( mode owner group dest )) {
        die "Missing key: $k in item" unless defined $file->{ $k };
    }
    my $line = "%attr($file->{ mode } $file->{ owner } $file->{ group }) $file->{ dest }";
    $line = "%config $line" if conf_p($file->{ dest });
    $line;
}

## is this a conf file?

sub conf_p {
    my $filename = shift;
    return 0;
}

## given spec hashref, write specfile

sub write_spec {
    my $x = shift;
    spew("$TOP/specfile", mk_spec($x));
}

## cp src file to dest or die; create dirs as needed

sub cpx {
    my($src, $dest, $mode) = @_;
    die "Invalid mode '$mode'" unless $mode =~ /^\d{4}$/;
    die "Not found: $src" unless -e $src;
    my @parts = split /\//, $dest;
    pop @parts;
    my @p2;
    while(@parts) {
        push @p2, shift @parts;
        my $dir = join('/', @p2);
        unless(-e $dir) {
            xmkdir($dir);
        }
    }
    system('/bin/cp', $src, $dest) && die "Failed to cp '$src' to '$dest'";
    system('/bin/chmod', $mode, $dest) && die "Failed to chmod '$dest'";
}
    
## given spec hashref, cp necessary files into tmp tree

sub cp_files {
    my $x = shift;
    my $files = get_files($x);
    foreach my $file(@$files) {
        $file->{ dest } =~ m|^/| or die "Dest path must start with /";
        cpx($file->{ src }, "$TOP/root$file->{ dest }", $file->{ mode });
    }
}

## mk dirs explicitly requested
## wait, is this any good?  rpm copy dirs?

sub mk_specified_dirs {
    my $x = shift;
    my $dirs = get_dirs($x);
    foreach my $dir(@$dirs) {
        system("mkdir -p -m $dir->{ mode } $TOP/root$dir->{ dest }") && die "Failed to mkdir '$dir->{ dest }'";
    }
}

#rpmbuild -bb --root `pwd`/root --define "_topdir /space/asher/sand/rpm/cdplayer-example/topdir" specfile2

## create rpm or die

sub xmk_rpm {
    chomp (my $here = `pwd`);
    my $rc = system(
        qq[rpmbuild -bb --root $here/$TOP/root --define "_topdir $here/$TOP" $TOP/specfile > $TOP/rpm.out 2>&1]);
    if($rc) {
        print STDERR "Error: see $TOP/rpm.out\n";
        exit -1;
    }
}

## given x and RPM, check that RPM has the right files or die

sub verify_rpm {
    my($x, $rpm) = @_;
    my $items = get_items($x);
    my $want_files = join(' ', sort map { $_->{ dest } } @$items );
    my $cmd = "rpm -q -p --filesbypkg $rpm";
    chomp(my @res = `$cmd`);
    my $have_files = join(' ', sort map { /\S+\s+(\S+)/ } @res)
        or die "No files found with '$cmd'";
    if($want_files ne $have_files) {
        print STDERR "RPM $rpm does not have expected files:\nWant: $want_files\n\nHave: $have_files\n\n$cmd\n";
        exit -1;
    }
}

sub get_rpm_path {
    chomp(my @res = `find $TOP/RPMS -type f`);
    die "RPM not found" unless @res; ## should never happen
    die "more than 1 rpm found" if @res > 1;
    $res[0];
}

## copy the new rpm up to this level or die

sub xcp_rpm_here {
    my $rpm_path = shift;
    $rpm_path =~ m|([^/]+)$| or die "Invalid rpm_path: '$rpm_path'";
    $FINAL_RPM_PATH = $1;
    system("cp $rpm_path .") && exit -1;
}

sub spew {
    my($fn, $page) = @_;
    open F, ">$fn" or die "Can't open $fn: $!";
    print F $page;
    close F;
}

## get files/dirs/all items, excluding defaults blocks

sub get_files {
    my $x = shift;
    [ grep { $_->{ type } eq 'file' && !$_->{ defaults } } @{ $x->{ items } } ];
}

sub get_dirs {
    my $x = shift;
    [ grep { $_->{ type } eq 'dir' && !$_->{ defaults } } @{ $x->{ items } } ];
}

sub get_items {
    my $x = shift;
    [ grep { !$_->{ defaults } } @{ $x->{ items } } ];
}

## return error msg or '' if valid

sub validate_hashref {
    my($val, $x) = @_;
    my @err;

    foreach my $key(keys %$x) {
        if(!$val->{ $key }) {
            push @err, "Unknown key: $key";
        }
        my $r0 = ref $val->{ $key }[0];
        my $r1 = ref $x->{ $key };
        if($r0 ne $r1) {
            push @err, "Wrong type: $key (got '$r1', expected '$r0)";
        }
    }
    foreach my $key(keys %$val) {
        if($val->{ $key }[1] && !$x->{ $key }) { ## mand && missing
            push @err, "Missing key: $key";
        }
    }
    join('; ', @err);
}

## validate or die with msg

sub xvalidate_hashref {
    my($val, $x, $name) = @_;
    my $err = validate_hashref($val, $x) or return;
    print STDERR "Error in $name: $err\n";
    exit -1;
}
    
sub validate_spec {
    my $spec = shift;
    xvalidate_hashref($TOP_VAL, $spec, 'top level');
    xvalidate_hashref($TAGS_VAL, $spec->{ tags }, 'tags');
    my $n = 0;
    my $items = get_items($spec);
    foreach my $item(@$items) {
        xvalidate_hashref($ITEM_VAL, $item, "item $n");
        $n ++;
    }
    1;
}

## add default vals to any items that lack them
## modifies spec

sub apply_defaults {
    my($x) = @_;
    my %d = ( type => 'file' );
    foreach my $item(@{ $x->{ items } }) {
        if($item->{ defaults }) { # it is a defaults block; modify our defaults
            while(my($k, $v) = each %$item) {
                next if $k eq 'defaults';
                $d{ $k } = $v;
            }
        }
        else { # apply defaults to this item
            while(my($k, $v) = each %d) {
                $item->{ $k } = $v unless defined $item->{ $k };
            }
        }
    }
}

sub apply_global_defaults {
    my($x) = @_;
    $x->{ cleanup } = 1 unless exists $x->{ cleanup };
}

## public

sub get_rpm_filename {
    $FINAL_RPM_PATH;
}

## public

sub get_example_spec {
    $X;
}

## public
## pass me a spec hashref

sub write_rpm {
    my($spec) = shift;
    apply_global_defaults($spec);
    apply_defaults($spec);
    validate_spec($spec);
    mk_dirs();
    write_spec($spec);
    cp_files($spec);
    mk_specified_dirs($spec);
    xmk_rpm();
    my $rpm_path = get_rpm_path();
    verify_rpm($spec, $rpm_path);
    xcp_rpm_here($rpm_path);
    rm_dirs() if $spec->{ cleanup };
    1;
}

1;
__END__

=head1 NAME

RPM::Make::DWIW - Create an RPM from a hashref

=head1 SYNOPSIS

use RPM::Make::DWIW;

    my $spec = {
        tags => {
            Summary     => 'ACME DB client',
            Name        => 'acmedb_client',
            Version     => '1.3',
            Release     => '3',
            License     => 'GPL',
            Group       => 'Applications/Database',
            #Source     => 'ftp://ftp.acme.com/acmedb_client-1.3.tar.gz',
            #URL        => 'http://www.acme.com/acmedb_client/',
            #Distribution => 'ACME',
            #Vendor     => 'ACME Software, Inc.',
            #Packager   => 'Adam Acme <aa@acme.com>',
        },
        description => 'Client libraries and binary for ACME DB',
        items => [
            # first set defaults for following items:
            {
                defaults => 1,
                type => 'file',
                mode => '0755',
                owner => 'root',
                group => 'wheel',
            },
            {
                src  => '../src/acme-client',
                dest => '/usr/bin/acme-client',
            },
            {
                src  => '../src/acme-client.conf',
                dest => '/etc/acme-client.conf',
                mode => '0644',
            },
            {
                src  => '../src/acme.so',
                dest => '/usr/lib/libacmeclient.so.1',
                mode => '0644',
            },
            {
                type => 'dir',
                dest => '/var/log/acme-client/transcripts',
            mode => '0777',
            },
        ],
        post => 'ldconfig',
        postun => 'ldconfig',
    };

    RPM::Make::DWIW::write_rpm($spec);

=head1 DESCRIPTION

This module creates an RPM package from a description hashref.

It has nothing to do with source code or build processes.  It assumes that whatever files you want to include in the RPM already exist.

This module can create RPMs for executable files, shared objects, or any
other installable file.  It is not specialized for installing Perl.

You control the ownership and permissions of each file as installed, independent of the ownership and permissions in the source tree or build directory.  You do not have to be root to create the RPM.

Under the covers, this module uses the rpmbuild command to create the RPM.
It also creates a temporary dir, which it removes if all went well.

=head2 Functions

=over 4

=item write_rpm($spec);

Write an RPM file from the given spec hashref.  Spec must contain:

=over 4

=item tags

A hashref of metadata specified by RPM.  The mandatory tags are Summary, Name, Version, License and Group.  The optional tags are Source, URL, Distribution, Vendor and Packager.  The meaning of these tags is specified by RPM.

=item description

The long description of the package.  May contain newlines.

=item items

An array of hashrefs, each representing a file or directory to include in the RPM, or a defaults block which sets defaults for subsequent items.

=over 4

=item src

Where you want to copy the file B<from> when building the RPM; typically a relative path into your build directory. Directories have no B<src>. 

=item dest

Location where you want RPM to install the file or create the directory when the RPM is installed.

=item mode

Access mode that you want the item to have after installation, e.g. '0755' for executables.  Must be a string, not a raw octal number.

=item owner, group

Unix user/group that you want the item to have after installation.

=item type

May be B<file> or B<dir>.  If it's B<file>, the item must have B<src>.

=item defaults

If defaults=1, this item does not represent a file/dir; it just sets defaults for all items downstream.  This way you can avoid repeating mode, user and group when you have several items that share the same settings.

The absence of a key in a B<defaults> block does not remove that key from the current defaults; to do that, set the value to "".

More than one B<defaults> block can occur in the items array.  Each B<defaults> block affects items downstream of it.  Each B<defaults> block inherits any defaults it does not override.

=back

Spec may also contain:

=over 4

=item requirements

An array of hashrefs, each having B<name> and optionally B<min_ver>.  Example:

    requirements => [
        {
            name        => 'libxml2',
            min_version => '2.6.0',
        }
    ]

This requires an RPM package called libxml2 B<or> a package offering that B<capability>.  The package must have verison 2.6.0 or higher.  

Use this to show dependency on other packages.  If your package includes executables or shared objects, RPM will examine them with ldd(1) and add dependencies.

=item pre, post, preun, postun

Shell commands to run pre/post installation and pre/post uninstallation.  May contain newlines.  If installing a shared object, generally include 'ldconfig' in both post and postun.

=item cleanup

By default this module removes its temp working directory if the RPM builds successfully.  If you want to preserve the directory, for instance to examine the specfile, set B<cleanup> = 0.

=back

=back

=item get_example_spec()

Get an example spec hashref.

=item get_rpm_filename()

Get the filename of the created RPM.  Only call this after creating an RPM.

=back

=head2 ERRORS

This module dies on errors.  This leaves the temporary build directory intact
for inspection.  In some cases, you may want to wrap the module in an eval.

=head1 SEE ALSO 

rpmbuild(8)

=head1 HISTORY

Written by Asher Blum E<lt>F<asher@wildsparx.com>E<gt> in 2010.

=head1 COPYRIGHT

Copyright (C) 2010 Asher Blum.  All rights reserved.
This code is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
