package Finance::Bank::BNPParibas;
use strict;
use Carp qw(carp croak);
use WWW::Mechanize;

#use LWP::Debug qw(+);
use vars qw($VERSION);

$VERSION = 0.05;

use constant BASE_URL        => 'https://www.secure.bnpparibas.net/controller?type=auth';
use constant LOGIN_FORM_NAME => 'logincanalnet';

=pod

=head1 NAME

Finance::Bank::BNPParibas -  Check your BNP bank accounts from Perl

=head1 SYNOPSIS

 use Finance::Bank::BNPParibas;

 my @accounts = Finance::Bank::BNPParibas->check_balance(
    username => "$username",  # Be sure to put the numbers
    password => "$password",  # between quote.
 );

 foreach my $account ( @accounts ){
    local $\ = "\n";
    print "       Name ", $account->name;
    print " Account_no ", $account->account_no;
    print "    Balance ", $account->balance;
    print "  Statement\n";

    foreach my $statement ( $account->statements ){
        print $statement->as_string;
    }
 }

=head1 DESCRIPTION

This module provides a rudimentary interface to the BNPNet online
banking system at L<https://www.bnpnet.bnp.fr/>. You will need
either Crypt::SSLeay or IO::Socket::SSL installed for HTTPS support
to work with LWP.

The interface of this module is directly taken from Simon Cozens'
Finance::Bank::LloydsTSB.

=head1 WARNING

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 METHODS

=head2 check_balance( username => $username, password => $password, ua => $ua )

Return a list of account (F::B::B::Account) objects, one for each of
your bank accounts. You can provide to this method a WWW::Mechanize
object as third argument.

=cut

sub check_balance {
    my ( $class, %opts ) = @_;
    croak "Must provide a password" unless exists $opts{password};
    croak "Must provide a username" unless exists $opts{username};

    my @accounts;

    $opts{ua} ||= WWW::Mechanize->new(
        agent      => "Finance::Bank::BNPParibas/$VERSION ($^O)",
        cookie_jar => {},
    );

    my $self = bless {%opts}, $class;

    my $orig_r;
    my $count = 0;
    {
        $orig_r = $self->{ua}->get(BASE_URL);

        # loop detected, try again
        ++$count;
        redo unless $orig_r->content || $count > 13;
    }
    croak $orig_r->error_as_HTML if $orig_r->is_error;

    # Check if the login form is in the page.
    $self->{ua}->quiet(1);
    $self->{ua}->form_name(LOGIN_FORM_NAME)
      or croak "Cannot find the login form '" . LOGIN_FORM_NAME . "'";

    # XXX Because the input below are created with javascript, we
    # have to manually add them to the Form.
    # see http://rt.cpan.org/NoAuth/Bug.html?id=2940
    $self->{ua}->{form}
      ->push_input( "text", { type => "text", name => "userid", value => "" } );
    $self->{ua}->{form}
	  ->push_input( "text", { type => "text", name => "password", value => "" } );

    $self->{ua}->set_fields(
        userid   => $self->{username},
        password => $self->{password},
    );

    my $click_r = $self->{ua}->submit;

    $self->{ua}->quiet(0);
    croak $click_r->error_as_HTML if $click_r->is_error;

    # XXX Without this header, bnpnet won't send the next page.
    $self->{ua}->add_header( Accept => 'text/html' );

    $self->{ua}->get('/SAF_TLC');

    # Check if the account download form is in the page.
    $self->{ua}->quiet(1);
    $self->{ua}->form_number(1)
      or croak "Cannot find the account download form";
    $self->{ua}->quiet(0);

    $self->{ua}->submit_form(
        form_number => 1,
        fields      => {
            ch_rop         => 'tous',
            ch_rop_fmt_fic => 'RTEXC',
            ch_rop_fmt_dat => 'JJMMAA',
            ch_rop_fmt_sep => 'VG',
            ch_rop_dat     => 'tous',
            ch_rop_dat_deb => '',
            ch_rop_dat_fin => '',
            ch_memo        => 'OUI',
        },
    );

    foreach ( @{ $self->{ua}->{links} } ) {
        my $qif = $_->[0];
        next unless $qif =~ /\.exl$/;

        my $qif_r = $self->{ua}->get($qif);
        carp $qif_r->error_as_HTML if $qif_r->is_error;

        next
          if $self->{ua}->{content} =~
          /<html>/i;    # no operation for this account
        push @accounts,
          Finance::Bank::BNPParibas::Account->new( $self->{ua}->content );
    }
    @accounts;
}

# The format of the date from BNPNet is DD/MM/YY, so we have to transform it to
# an ISO format: YYYY-MM-DD
sub _normalize_date {
    my $date = shift;
    my ( $d, $m, $y ) = split ( /\//, $date );
    $y = $y =~ /^[789]\d$/ ? $y + 1900 : $y + 2000;
    return "$y-$m-$d";
}

package Finance::Bank::BNPParibas::Account;

=pod

=head1 Account methods

=head2 sort_code()

Return the sort code of the account. Currently, it returns an
undefined value.

=head2 name()

Returns the human-readable name of the account.

=head2 account_no()

Return the account number, in the form C<XXX YYYYYYYYY ZZ>, where X, Y
and Z are numbers.

=head2 balance()

Returns the balance of the account. Note that the BNP site displays them
in French format (i.e C<123,75>), but the string returns a number perl
understands (i.e C<123.75>).

=head2 statements()

Return a list of Statement object (Finance::Bank::BNPParibas::Statement).

=cut

sub new {
    my $class = shift;
    chomp( my @content = split ( /\n/, shift ) );
    my $header = shift @content;

    my ( $name, $account_no, $date, $balance ) =
      ( $header =~
          m/^(.+)\s+(\d{5}\s+\d{9}\s+\d{2})\t+(\d{2}\/\d{2}\/\d{2})\t+(\d+,\d+)/
      );

    $balance =~ s/,/./;

    my @statements;
    push @statements,
      Finance::Bank::BNPParibas::Statement->new($_) foreach @content;

    $date = Finance::Bank::BNPParibas::_normalize_date($date);

    bless {
        name       => $name,
        account_no => $account_no,
        sort_code  => undef,
        date       => $date,
        balance    => $balance,
        statements => [@statements],
    }, $class;
}

sub sort_code  { undef }
sub name       { $_[0]->{name} }
sub account_no { $_[0]->{account_no} }
sub balance    { $_[0]->{balance} }
sub statements { @{ $_[0]->{statements} } }

package Finance::Bank::BNPParibas::Statement;

=pod

=head1 Statement methods

=head2 date()

Returns the date when the statement occured, in YYYY-MM-DD format.

=head2 description()

Returns a brief description of the statement.

=head2 amount()

Returns the amount of the statement (expressed in Euros).

=head2 as_string($separator)

Returns a tab-delimited representation of the statement. By default, it
uses a tabulation to separate the fields, but the user can provide its
own separator.

=cut

sub new {
    my $class     = shift;
    my $statement = shift;

    my @entry = split ( /\t/, $statement );

    $entry[0] = Finance::Bank::BNPParibas::_normalize_date( $entry[0] );
    $entry[1] =~ s/\s+/ /g;
    $entry[2] =~ s/,/./;

    bless [ @entry[ 0 .. 2 ] ], $class;
}

sub date        { $_[0]->[0] }
sub description { $_[0]->[1] }
sub amount      { $_[0]->[2] }

sub as_string { join ( $_[1] || "\t", @{ $_[0] } ) }

1;

__END__

=head1 BUGS

Please report any bugs or comments using the Request Tracker interface:
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Finance-Bank-BNPParibas>

=head1 COPYRIGHT

Copyright 2002-2003, Briac Pilpré. All Rights Reserved. This module can be
redistributed under the same terms as Perl itself.

=head1 AUTHOR

Briac Pilpré <briac@cpan.org>

Thanks to Simon Cozens for releasing Finance::Bank::LloydsTSB

=head1 SEE ALSO

Finance::Bank::LloydsTSB, WWW::Mechanize

=cut

