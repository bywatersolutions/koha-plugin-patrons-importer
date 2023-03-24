package Koha::Plugin::Com::ByWaterSolutions::PatronsImporter;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use Koha::Encryption;

use File::Temp qw(tempdir);
use Net::SFTP::Foreign;
use Try::Tiny;

## Here we set our plugin version
our $VERSION         = "{VERSION}";
our $MINIMUM_VERSION = "{MINIMUM_VERSION}";

our $metadata = {
    name            => 'Patrons Importer',
    author          => 'Kyle M Hall',
    date_authored   => '2022-12-02',
    date_updated    => "1900-01-01",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Automate importing patron CSV files from SFTP',
};

=head3 new

=cut

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        if ( $cgi->param('sync') ) {
            $self->cronjob_nightly( { send_sync_report => 1 } );
            $template->param( sync_report_ran => 1, );
        }

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            debug      => $self->retrieve_data('debug'),
            run_on_dow => $self->retrieve_data('run_on_dow'),
            host       => $self->retrieve_data('host'),
            username   => $self->retrieve_data('username'),
            password   => $self->retrieve_data('password')
            ? Koha::Encryption->new->decrypt_hex(
                $self->retrieve_data('password')
              )
            : q{},
            dir                   => $self->retrieve_data('dir'),
            filename              => $self->retrieve_data('filename'),
            confirm               => $self->retrieve_data('confirm'),
            matchpoint            => $self->retrieve_data('matchpoint'),
            default               => $self->retrieve_data('default'),
            overwrite             => $self->retrieve_data('overwrite'),
            preserve_field        => $self->retrieve_data('preserve_field'),
            update_expiration     => $self->retrieve_data('update_expiration'),
            verbose               => $self->retrieve_data('verbose'),
            extra_options         => $self->retrieve_data('extra_options'),
            expiration_from_today =>
              $self->retrieve_data('expiration_from_today'),
            preserve_extended_attributes =>
              $self->retrieve_data('preserve_extended_attributes'),
        );

        if ( $cgi->param('test') ) {
            try {
                my $sftp = $self->get_sftp();
            }
            catch {
                $template->param( test_error => $_ );
            };

            $template->param( test_completed => 1 );
        }

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                debug      => $cgi->param('debug'),
                run_on_dow => $cgi->param('run_on_dow'),
                host       => $cgi->param('host'),
                username   => $cgi->param('username'),
                password   =>
                  Koha::Encryption->new->encrypt_hex( $cgi->param('password') ),
                dir                   => $cgi->param('dir'),
                filename              => $cgi->param('filename'),
                confirm               => $cgi->param('confirm'),
                matchpoint            => $cgi->param('matchpoint'),
                default               => $cgi->param('default'),
                overwrite             => $cgi->param('overwrite'),
                preserve_field        => $cgi->param('preserve_field'),
                update_expiration     => $cgi->param('update_expiration'),
                verbose               => $cgi->param('verbose'),
                extra_options         => $cgi->param('extra_options'),
                expiration_from_today => $cgi->param('expiration_from_today'),
                preserve_extended_attributes =>
                  $cgi->param('preserve_extended_attributes'),
            }
        );
        $self->go_home();
    }
}

sub get_sftp {
    my ($self)        = @_;
    my $sftp_host     = $self->retrieve_data('host');
    my $sftp_username = $self->retrieve_data('username');
    my $sftp_password =
      Koha::Encryption->new->decrypt_hex( $self->retrieve_data('password') );
    my $sftp_dir = $self->retrieve_data('dir');

    my $sftp = Net::SFTP::Foreign->new(
        host     => $sftp_host,
        user     => $sftp_username,
        port     => 22,
        password => $sftp_password
    );
    $sftp->die_on_error(
        "Patrons Importer - SFTP ERROR: Unable to establish SFTP connection");

    $sftp->setcwd($sftp_dir)
      or die "Patrons Importer - SFTP ERROR: unable to change cwd: "
      . $sftp->error;

    return $sftp;
}

=head3 cronjob_nightly

=cut

sub cronjob_nightly {
    my ( $self, $p ) = @_;

    my $debug = $self->retrieve_data('debug');

    my $run_on_dow = $self->retrieve_data('run_on_dow');
    if ($run_on_dow) {
        if ( (localtime)[6] == $run_on_dow ) {
            say "Run on Day of Week $run_on_dow matches current day of week "
              . (localtime)[6]
              if $debug >= 1;
        }
        else {
            say
"Run on Day of Week $run_on_dow does not match current day of week "
              . (localtime)[6]
              if $debug >= 1;
            return;
        }
    }

    my $sftp_filename = $self->retrieve_data('filename');

    my $sftp = $self->get_sftp();

    my $tempdir = tempdir();
    #$sftp->setcwd($sftp_dir) or die "unable to change cwd: " . $sftp->error;

    my $tempdir = tempdir();

    warn qq{DOWNLOADING '$sftp_dir/$sftp_filename' TO '$tempdir/$sftp_filename'};
    $sftp->get( "$sftp_dir/$sftp_filename", "$tempdir/$sftp_filename" )
      or die "Patrons Importer - SFTP ERROR: get failed: " . $sftp->error;

    my $confirm               = $self->retrieve_data('confirm');
    my $matchpoint            = $self->retrieve_data('matchpoint');
    my $default               = $self->retrieve_data('default');
    my $overwrite             = $self->retrieve_data('overwrite');
    my $preserve_field        = $self->retrieve_data('preserve_field');
    my $update_expiration     = $self->retrieve_data('update_expiration');
    my $expiration_from_today = $self->retrieve_data('expiration_from_today');
    my $verbose               = $self->retrieve_data('verbose');
    my $extra_options         = $self->retrieve_data('extra_options');
    my $preserve_extended_attributes =
      $self->retrieve_data('preserve_extended_attributes');

    my $cmd =
      qq{/usr/share/koha/bin/import_patrons.pl --file $tempdir/$sftp_filename};

    $cmd .= " --confirm"                        if $confirm;
    $cmd .= " --matchpoint $matchpoint"         if $matchpoint;
    $cmd .= " --default $default"               if $default;
    $cmd .= " --overwrite"                      if $overwrite;
    $cmd .= " --preserve_field $preserve_field" if $preserve_field;
    $cmd .= " --preserve-extended-attributes" if $preserve_extended_attributes;
    $cmd .= " --update-expiration"            if $update_expiration;
    $cmd .= " --expiration-from-today"        if $expiration_from_today;
    $cmd .= " --verbose"                      if $verbose;
    $cmd .= " $extra_options"                 if $extra_options;

    say "COMMAND: $cmd";
    my $output = qx{$cmd};
    say "COMMAND OUTPUT: $output";

    #unlink "$tempdir/$sftp_filename";
}

=head3 install

This is the 'install' method. Any database tables or other setup that should
be done when the plugin if first installed should be executed in this method.
The installation method should always return true if the installation succeeded
or false if it failed.

=cut

sub install() {
    my ( $self, $args ) = @_;

    $self->store_data(
        {
            run_on_dow => "0",
        }
    );

    return 1;
}

=head3 upgrade

This is the 'upgrade' method. It will be triggered when a newer version of a
plugin is installed over an existing older version of a plugin

=cut

sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

=head3 uninstall

This method will be run just before the plugin files are deleted
when a plugin is uninstalled. It is good practice to clean up
after ourselves!

=cut

sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

1;
