#=====================================================================
# SQL-Ledger ERP
# Copyright (C) 2022
#
#  Author: Tekki
#     Web: https://tekki.ch
#
#======================================================================
#
# Spreadsheet Functions for Yearend Reports
#
#======================================================================

$form->load_module(['Excel::Writer::XLSX', 'SL::Spreadsheet'], $locale->text('Module not installed:'));

sub create_spreadsheet {
  my ($report_code, $periods) = @_;
  
  my $ss = SL::Spreadsheet->new($form, $userspath);
  
  # structure
  my %spreadsheet_info = (
    columns => {
      accno => 'text',
      description => 'text',
    }
  );

  my (@column_index, @amount_columns);
  if ($form->{previousyear}) {
    if ($form->{reversedisplay}) {
      @amount_columns = map { ("previous_$_", "this_$_") } @$periods;
    } else {
      @amount_columns = map { ("this_$_", "previous_$_") } @$periods;
    }
  } else {
    @amount_columns = map {"this_$_"} @$periods;
  }
  my $tab = $form->{l_accno} ? 1 : 0;
  push @column_index, 'accno' if $tab;
  push @column_index, 'description', @amount_columns;

  $spreadsheet_info{header}{$_} = 'date' for @amount_columns;

  $ss->structure(\%spreadsheet_info)->column_index(\@column_index)->maxwidth(50);
  
  $ss->text($form->{company})->crlf;
  $ss->text($_)->crlf for split /\n/, $form->{address};
  $ss->crlf;

  my (@categories, %header_data);
  if ($report_code eq 'balance_sheet') {
    $form->{title} = $locale->text('Balance Sheet');
    @categories = qw|A L Q|;

    $ss->title($form->{title})->crlf(2);
    $ss->tab($tab)->text($locale->text('as at'), 'heading4')
      ->lf->date($form->{todate}, 'heading4')->crlf(2);
  } else {
    $form->{title} = $locale->text('Income Statement');
    @categories = qw|I E|;

    $ss->title($form->{title})->crlf(2);
    $ss->tab($tab)->text($locale->text('for Period'), 'heading4')
      ->lf->date($form->{fromdate}, 'heading4')->lf->date($form->{todate}, 'heading4')->crlf(2);

    for my $column (@amount_columns) {
      $column =~ /(.*)_(.*)/;
      $header_data{$column} = $form->{period}{$2}{$1}{fromdate};
    }
    $ss->header_row(\%header_data, format => 'heading4');
  }

  for my $column (@amount_columns) {
    $column =~ /(.*)_(.*)/;
    $header_data{$column} = $form->{period}{$2}{$1}{todate};
  }
  $ss->header_row(\%header_data)->freeze_panes(undef, $tab + 1);

  my %total = (description => $locale->text('Income / (Loss)'));
  &_ss_section($ss, $_, \@amount_columns, \%total) for @categories;

  $ss->data_row(\%total, format => 'total') if $report_code eq 'income_statement';

  $ss->finish;
}

sub _ss_section {
  my ($ss, $category, $amount_columns, $total) = @_;

  my %subtotal;
  my %accounts = (
    A => $locale->text('Assets'),
    E => $locale->text('Expenses'),
    I => $locale->text('Income'),
    L => $locale->text('Liabilities'),
    Q => $locale->text('Equity'),
  );

  my %column_data = (description => $accounts{$category});
  $ss->data_row(\%column_data, format => 'subsubtotal');

  my $ml             = $category =~ /I|L|Q/ ? 1 : -1;
  my $print_subtotal = 0;
  for my $accno (sort keys %{$form->{$category}}) {
    my $charttype = $form->{$category}{$accno}{this}{0}{charttype};
    my $do_print
      = $charttype eq 'H' && $form->{l_heading} || $charttype eq 'A' && $form->{l_account};

    if ($print_subtotal && $charttype eq 'H') {
      &_ss_subtotal($ss, \%subtotal);
    }

    $print_subtotal = 1;

    %column_data = (accno => $accno, description => $form->{accounts}{$accno}{description});
    if ($charttype eq 'H') {
      %subtotal = (accno => $accno, description => $form->{accounts}{$accno}{description});
    }

    for my $column (@$amount_columns) {
      my ($year, $period) = $column =~ /(.*)_(.*)/;
      if ($charttype eq 'H') {
        $subtotal{$column} = $form->{$category}{$accno}{$year}{$period}{amount} * $ml;
        $form->{$category}{$accno}{$year}{$period}{amount} = 0;
      }

      my $amount = $form->{$category}{$accno}{$year}{$period}{amount};
      $column_data{$column} = $amount * $ml || '';

      $total->{$category}{$column} += $amount * $ml;
      $total->{$column} += $amount;
    }

    $ss->data_row(\%column_data) if $do_print;
  }

  if ($category eq 'Q') {
    %column_data = (description => $locale->text('Current Earnings'));

    for my $column (@$amount_columns) {
      my ($year, $period) = $column =~ /(.*)_(.*)/;

      my $currentearnings
        = $total->{A}{$column} - $total->{L}{$column} - $total->{Q}{$column};
      $column_data{$column} = $currentearnings;

      $subtotal{$column} += $currentearnings if $form->{l_subtotal} && $form->{l_heading};
      $total->{Q}{$column} += $currentearnings;
    }

    $ss->data_row(\%column_data);
  }

  &_ss_subtotal($ss, \%subtotal); 

  %column_data
    = (description => $locale->text('Total') . qq| $accounts{$category}|, %{$total->{$category}});
  $ss->data_row(\%column_data, format => 'subtotal')->crlf;
}

sub _ss_subtotal {
  my ($ss, $subtotal) = @_;

  if ($form->{l_subtotal} && $subtotal->{accno}){
    $ss->data_row($subtotal, format => 'subsubtotal')->crlf;
    $subtotal = {};
  }
}

sub download_spreadsheet {
  &create_spreadsheet(@_);
  $form->download_tmpfile('application/vnd.ms-excel', "$form->{title}-$form->{company}.xlsx");

  exit;
}

1;

=encoding utf8

=head1 NAME

bin/mozilla/rpss.pl - Spreadsheet Functions for Yearend Reports

=head1 DESCRIPTION

L<bin::mozilla::ss> contains functions to create and download spreadsheets for yearend reports.

=head1 DEPENDENCIES

L<bin::mozilla::ss>

=over

=item * uses
L<Excel::Writer::XLSX>

=back

=head1 FUNCTIONS

L<bin::mozilla::ss> implements the following functions:

=head2 create_spreadsheet

  &create_spreadsheet($spreadsheet_info, $report_options, $column_index, $header, $data);

=head2 download_spreadsheet

  &download_spreadsheet($spreadsheet_info, $report_options, $column_index, $header, $data);

=cut
