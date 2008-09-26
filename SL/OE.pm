#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 2001
#
#  Author: DWS Systems Inc.
#     Web: http://www.sql-ledger.org
#
#  Contributors:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Order entry module
# Quotation
#
#======================================================================

package OE;


sub transactions {
  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
 
  my $query;
  my $ordnumber = 'ordnumber';
  my $quotation = '0';
  my ($null, $department_id) = split /--/, $form->{department};

  my $department = " AND o.department_id = $department_id" if $department_id;
  
  my $rate = ($form->{vc} eq 'customer') ? 'buy' : 'sell';

  ($form->{transdatefrom}, $form->{transdateto}) = $form->from_to($form->{year}, $form->{month}, $form->{interval}) if $form->{year} && $form->{month};

  if ($form->{type} =~ /_quotation$/) {
    $quotation = '1';
    $ordnumber = 'quonumber';
  }
  
  my $number = $form->like(lc $form->{$ordnumber});
  my $name = $form->like(lc $form->{$form->{vc}});
  
  my $query = qq|SELECT o.id, o.ordnumber, o.transdate, o.reqdate,
                 o.amount, ct.name, o.netamount, o.$form->{vc}_id,
		 ex.$rate AS exchangerate,
		 o.closed, o.quonumber, o.shippingpoint, o.shipvia,
		 e.name AS employee, m.name AS manager, o.curr, o.ponumber
	         FROM oe o
	         JOIN $form->{vc} ct ON (o.$form->{vc}_id = ct.id)
	         LEFT JOIN employee e ON (o.employee_id = e.id)
		 LEFT JOIN employee m ON (e.managerid = m.id)
	         LEFT JOIN exchangerate ex ON (ex.curr = o.curr
		                               AND ex.transdate = o.transdate)
	         WHERE o.quotation = '$quotation'
		 $department|;

  my %ordinal = ( id => 1,
                  ordnumber => 2,
                  transdate => 3,
		  reqdate => 4,
		  name => 6,
		  quonumber => 11,
		  shipvia => 13,
		  employee => 14,
		  manager => 15,
		  ponumber => 17
		);

  my @a = (transdate, $ordnumber, name);
  push @a, "employee" if $form->{l_employee};
  if ($form->{type} !~ /(ship|receive)_order/) {
    push @a, "manager" if $form->{l_manager};
  }
  my $sortorder = $form->sort_order(\@a, \%ordinal);
  
  
  # build query if type eq (ship|receive)_order
  if ($form->{type} =~ /(ship|receive)_order/) {
    
    my ($warehouse, $warehouse_id) = split /--/, $form->{warehouse};

    $query =  qq|SELECT DISTINCT o.id, o.ordnumber, o.transdate,
                 o.reqdate, o.amount, ct.name, o.netamount, o.$form->{vc}_id,
		 ex.$rate AS exchangerate,
		 o.closed, o.quonumber, o.shippingpoint, o.shipvia,
		 e.name AS employee, o.curr, o.ponumber
	         FROM oe o
	         JOIN $form->{vc} ct ON (o.$form->{vc}_id = ct.id)
		 JOIN orderitems oi ON (oi.trans_id = o.id)
		 JOIN parts p ON (p.id = oi.parts_id)|;

      if ($warehouse_id && $form->{type} eq 'ship_order') {
	$query .= qq|
	         JOIN inventory i ON (oi.parts_id = i.parts_id)
		 |;
      }

    $query .= qq|
	         LEFT JOIN employee e ON (o.employee_id = e.id)
	         LEFT JOIN exchangerate ex ON (ex.curr = o.curr
		                               AND ex.transdate = o.transdate)
	         WHERE o.quotation = '0'
		 AND (p.inventory_accno_id > 0 OR p.assembly = '1')
		 AND oi.qty != oi.ship
		 $department|;
		 
    if ($warehouse_id && $form->{type} eq 'ship_order') {
      $query .= qq|
                 AND i.warehouse_id = $warehouse_id
		 AND ( SELECT SUM(i.qty)
		       FROM inventory i
		       WHERE oi.parts_id = i.parts_id
		       AND i.warehouse_id = $warehouse_id ) > 0
		 |;
    }

  }

  if ($form->{"$form->{vc}_id"}) {
    $query .= qq| AND o.$form->{vc}_id = $form->{"$form->{vc}_id"}|;
  } else {
    if ($form->{$form->{vc}} ne "") {
      $query .= " AND lower(ct.name) LIKE '$name'";
    }
  }

  if ($form->{$ordnumber} ne "") {
    $query .= " AND lower($ordnumber) LIKE '$number'";
    $form->{open} = 1;
    $form->{closed} = 1;
  }
  if ($form->{ponumber} ne "") {
    $query .= " AND lower(ponumber) LIKE '$form->{ponumber}'";
  }

  if (!$form->{open} && !$form->{closed}) {
    $query .= " AND o.id = 0";
  } elsif (!($form->{open} && $form->{closed})) {
    $query .= ($form->{open}) ? " AND o.closed = '0'" : " AND o.closed = '1'";
  }

  if ($form->{shipvia} ne "") {
    $var = $form->like(lc $form->{shipvia});
    $query .= " AND lower(o.shipvia) LIKE '$var'";
  }
  if ($form->{description} ne "") {
    $var = $form->like(lc $form->{description});
    $query .= " AND o.id IN (SELECT DISTINCT trans_id
                             FROM orderitems
			     WHERE lower(description) LIKE '$var')";
  }

  if ($form->{transdatefrom}) {
    $query .= " AND o.transdate >= '$form->{transdatefrom}'";
  }
  if ($form->{transdateto}) {
    $query .= " AND o.transdate <= '$form->{transdateto}'";
  }

  $query .= " ORDER by $sortorder";

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  my %oid = ();
  while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {
    $ref->{exchangerate} = 1 unless $ref->{exchangerate};
    push @{ $form->{OE} }, $ref if $ref->{id} != $oid{$ref->{id}};
    $oid{$ref->{id}} = $ref->{id};
  }
  $sth->finish;

  $dbh->disconnect;
  
}



sub save {
  my ($self, $myconfig, $form) = @_;
  
  # connect to database, turn off autocommit
  my $dbh = $form->dbconnect_noauto($myconfig);

  my $query;
  my $sth;
  my $null;
  my $exchangerate = 0;

  ($null, $form->{employee_id}) = split /--/, $form->{employee};
  if (! $form->{employee_id}) {
    ($form->{employee}, $form->{employee_id}) = $form->get_employee($dbh);
    $form->{employee} = "$form->{employee}--$form->{employee_id}";
  }

  my $ml = ($form->{type} eq 'sales_order') ? 1 : -1;

  $query = qq|SELECT p.assembly, p.project_id
	      FROM parts p
	      WHERE p.id = ?|;
  my $pth = $dbh->prepare($query) || $form->dberror($query);

 
  if ($form->{id}) {
    $query = qq|SELECT id FROM oe
                WHERE id = $form->{id}|;

    if ($dbh->selectrow_array($query)) {
      &adj_onhand($dbh, $form, $ml) if $form->{type} =~ /_order$/;
      
      $query = qq|DELETE FROM orderitems
		  WHERE trans_id = $form->{id}|;
      $dbh->do($query) || $form->dberror($query);

      $query = qq|DELETE FROM shipto
		  WHERE trans_id = $form->{id}|;
      $dbh->do($query) || $form->dberror($query);
      
    } else {
      $query = qq|INSERT INTO oe (id)
                  VALUES ($form->{id})|;
      $dbh->do($query) || $form->dberror($query);
    }
  }
 
  if (! $form->{id}) {
    
    my $uid = time;
    $uid .= $$;
    
    $query = qq|INSERT INTO oe (ordnumber, employee_id)
		VALUES ('$uid', $form->{employee_id})|;
    $dbh->do($query) || $form->dberror($query);
   
    $query = qq|SELECT id FROM oe
                WHERE ordnumber = '$uid'|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);
    ($form->{id}) = $sth->fetchrow_array;
    $sth->finish;
    
  }

  my $amount;
  my $linetotal;
  my $discount;
  my $project_id;
  my $taxrate;
  my $taxamount;
  my $fxsellprice;
  my %taxbase;
  my @taxaccounts;
  my %taxaccounts;
  my $netamount = 0;

 
  for my $i (1 .. $form->{rowcount}) {

    for (qw(qty ship)) { $form->{"${_}_$i"} = $form->parse_amount($myconfig, $form->{"${_}_$i"}) }
     
    $form->{"discount_$i"} = $form->parse_amount($myconfig, $form->{"discount_$i"}) / 100;
    $form->{"sellprice_$i"} = $form->parse_amount($myconfig, $form->{"sellprice_$i"});
 
    if ($form->{"qty_$i"}) {

      $pth->execute($form->{"id_$i"});
      $ref = $pth->fetchrow_hashref(NAME_lc);
      for (keys %$ref) { $form->{"${_}_$i"} = $ref->{$_} }
      $pth->finish;

      $fxsellprice = $form->{"sellprice_$i"};

      my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
      $dec = length $dec;
      my $decimalplaces = ($dec > 2) ? $dec : 2;

      $discount = $form->round_amount($form->{"sellprice_$i"} * $form->{"discount_$i"}, $decimalplaces);
      $form->{"sellprice_$i"} = $form->round_amount($form->{"sellprice_$i"} - $discount, $decimalplaces);

      $linetotal = $form->round_amount($form->{"sellprice_$i"} * $form->{"qty_$i"}, 2);
      
      @taxaccounts = split / /, $form->{"taxaccounts_$i"};
      $taxrate = 0;
      $taxdiff = 0;
      
      for (@taxaccounts) { $taxrate += $form->{"${_}_rate"} }

      if ($form->{taxincluded}) {
	$taxamount = $linetotal * $taxrate / (1 + $taxrate);
	$taxbase = $linetotal - $taxamount;
	# we are not keeping a natural price, do not round
	$form->{"sellprice_$i"} = $form->{"sellprice_$i"} * (1 / (1 + $taxrate));
      } else {
	$taxamount = $linetotal * $taxrate;
	$taxbase = $linetotal;
      }

      if (@taxaccounts && $form->round_amount($taxamount, 2) == 0) {
	if ($form->{taxincluded}) {
	  foreach $item (@taxaccounts) {
	    $taxamount = $form->round_amount($linetotal * $form->{"${item}_rate"} / (1 + abs($form->{"${item}_rate"})), 2);

	    $taxaccounts{$item} += $taxamount;
	    $taxdiff += $taxamount; 

	    $taxbase{$item} += $taxbase;
	  }
	  $taxaccounts{$taxaccounts[0]} += $taxdiff;
	} else {
	  foreach $item (@taxaccounts) {
	    $taxaccounts{$item} += $linetotal * $form->{"${item}_rate"};
	    $taxbase{$item} += $taxbase;
	  }
	}
      } else {
	foreach $item (@taxaccounts) {
	  $taxaccounts{$item} += $taxamount * $form->{"${item}_rate"} / $taxrate;
	  $taxbase{$item} += $taxbase;
	}
      }


      $netamount += $form->{"sellprice_$i"} * $form->{"qty_$i"};
      
      $project_id = 'NULL';
      if ($form->{"projectnumber_$i"} ne "") {
	($null, $project_id) = split /--/, $form->{"projectnumber_$i"};
      }
      $project_id = $form->{"project_id_$i"} if $form->{"project_id_$i"};
      
      # save detail record in orderitems table
      $query = qq|INSERT INTO orderitems (|;
      $query .= "id, " if $form->{"orderitems_id_$i"};
      $query .= qq|trans_id, parts_id, description, qty, sellprice, discount,
		   unit, reqdate, project_id, serialnumber, ship)
                   VALUES (|;
      $query .= qq|$form->{"orderitems_id_$i"},| if $form->{"orderitems_id_$i"};
      $query .= qq|$form->{id}, $form->{"id_$i"}, |
		   .$dbh->quote($form->{"description_$i"}).qq|,
		   $form->{"qty_$i"}, $fxsellprice, $form->{"discount_$i"}, |
		   .$dbh->quote($form->{"unit_$i"}).qq|, |
		   .$form->dbquote($form->{"reqdate_$i"}, SQL_DATE).qq|, 
		   $project_id, |
		   .$dbh->quote($form->{"serialnumber_$i"}).qq|,
		   $form->{"ship_$i"})|;
      $dbh->do($query) || $form->dberror($query);

      $form->{"sellprice_$i"} = $fxsellprice;
    }
    $form->{"discount_$i"} *= 100;
  }


  # set values which could be empty
  for (qw(vendor_id customer_id taxincluded closed quotation)) { $form->{$_} *= 1 }

  # add up the tax
  my $tax = 0;
  for (keys %taxaccounts) { $tax += $form->round_amount($taxaccounts{$_}, 2) }
  
  $amount = $form->round_amount($netamount + $tax, 2);
  $netamount = $form->round_amount($netamount, 2);

  if ($form->{currency} eq $form->{defaultcurrency}) {
    $form->{exchangerate} = 1;
  } else {
    $exchangerate = $form->check_exchangerate($myconfig, $form->{currency}, $form->{transdate}, ($form->{vc} eq 'customer') ? 'buy' : 'sell');
  }
  
  $form->{exchangerate} = ($exchangerate) ? $exchangerate : $form->parse_amount($myconfig, $form->{exchangerate});
  
  my $quotation;
  my $ordnumber;
  my $numberfld;
  if ($form->{type} =~ /_order$/) {
    $quotation = "0";
    $ordnumber = "ordnumber";
    $numberfld = ($form->{vc} eq 'customer') ? "sonumber" : "ponumber";
  } else {
    $quotation = "1";
    $ordnumber = "quonumber";
    $numberfld = ($form->{vc} eq 'customer') ? "sqnumber" : "rfqnumber";
  }

  $form->{$ordnumber} = $form->update_defaults($myconfig, $numberfld, $dbh) unless $form->{$ordnumber}; 
  
  ($null, $form->{department_id}) = split(/--/, $form->{department});
  for (qw(department_id terms)) { $form->{$_} *= 1 }

  # save OE record
  $query = qq|UPDATE oe set
	      ordnumber = |.$dbh->quote($form->{ordnumber}).qq|,
	      quonumber = |.$dbh->quote($form->{quonumber}).qq|,
              transdate = '$form->{transdate}',
              vendor_id = $form->{vendor_id},
	      customer_id = $form->{customer_id},
              amount = $amount,
              netamount = $netamount,
	      reqdate = |.$form->dbquote($form->{reqdate}, SQL_DATE).qq|,
	      taxincluded = '$form->{taxincluded}',
	      shippingpoint = |.$dbh->quote($form->{shippingpoint}).qq|,
	      shipvia = |.$dbh->quote($form->{shipvia}).qq|,
	      notes = |.$dbh->quote($form->{notes}).qq|,
	      intnotes = |.$dbh->quote($form->{intnotes}).qq|,
	      curr = '$form->{currency}',
	      closed = '$form->{closed}',
	      quotation = '$quotation',
	      department_id = $form->{department_id},
	      employee_id = $form->{employee_id},
	      language_code = '$form->{language_code}',
	      ponumber = |.$dbh->quote($form->{ponumber}).qq|,
	      terms = $form->{terms}
              WHERE id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);

  $form->{ordtotal} = $amount;

  # add shipto
  $form->{name} = $form->{$form->{vc}};
  $form->{name} =~ s/--$form->{"$form->{vc}_id"}//;
  $form->add_shipto($dbh, $form->{id});

  # save printed, emailed, queued
  $form->save_status($dbh); 
    
  if (($form->{currency} ne $form->{defaultcurrency}) && !$exchangerate) {
    if ($form->{vc} eq 'customer') {
      $form->update_exchangerate($dbh, $form->{currency}, $form->{transdate}, $form->{exchangerate}, 0);
    }
    if ($form->{vc} eq 'vendor') {
      $form->update_exchangerate($dbh, $form->{currency}, $form->{transdate}, 0, $form->{exchangerate});
    }
  }
  

  if ($form->{type} =~ /_order$/) {
    # adjust onhand
    &adj_onhand($dbh, $form, $ml * -1);
    &adj_inventory($dbh, $myconfig, $form);
  }

  my %audittrail = ( tablename	=> 'oe',
                     reference	=> ($form->{type} =~ /_order$/) ? $form->{ordnumber} : $form->{quonumber},
		     formname	=> $form->{type},
		     action	=> 'saved',
		     id		=> $form->{id} );

  $form->audittrail($dbh, "", \%audittrail);

  $form->save_recurring($dbh, $myconfig);
  
  my $rc = $dbh->commit;
  $dbh->disconnect;

  $rc;
  
}



sub delete {
  my ($self, $myconfig, $form, $spool) = @_;

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  # delete spool files
  my $query = qq|SELECT spoolfile FROM status
                 WHERE trans_id = $form->{id}
		 AND spoolfile IS NOT NULL|;
  $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  my $spoolfile;
  my @spoolfiles = ();

  while (($spoolfile) = $sth->fetchrow_array) {
    push @spoolfiles, $spoolfile;
  }
  $sth->finish;


  $query = qq|SELECT o.parts_id, o.ship, p.inventory_accno_id, p.assembly
              FROM orderitems o
	      JOIN parts p ON (p.id = o.parts_id)
              WHERE trans_id = $form->{id}|;
  $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  if ($form->{type} =~ /_order$/) {
    $ml = ($form->{type} eq 'purchase_order') ? -1 : 1;
    while (my ($id, $ship, $inv, $assembly) = $sth->fetchrow_array) {
      $form->update_balance($dbh,
			    "parts",
			    "onhand",
			    qq|id = $id|,
			    $ship * $ml) if ($inv || $assembly);
    }
  }
  $sth->finish;

  # delete inventory
  $query = qq|DELETE FROM inventory
              WHERE trans_id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);
  
  # delete status entries
  $query = qq|DELETE FROM status
              WHERE trans_id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);
  
  # delete OE record
  $query = qq|DELETE FROM oe
              WHERE id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);

  # delete individual entries
  $query = qq|DELETE FROM orderitems
              WHERE trans_id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);

  $query = qq|DELETE FROM shipto
              WHERE trans_id = $form->{id}|;
  $dbh->do($query) || $form->dberror($query);
  
  my %audittrail = ( tablename	=> 'oe',
                     reference	=> ($form->{type} =~ /_order$/) ? $form->{ordnumber} : $form->{quonumber},
		     formname	=> $form->{type},
		     action	=> 'deleted',
		     id		=> $form->{id} );

  $form->audittrail($dbh, "", \%audittrail);
  
  my $rc = $dbh->commit;
  $dbh->disconnect;

  if ($rc) {
    foreach $spoolfile (@spoolfiles) {
      unlink "$spool/$spoolfile" if $spoolfile;
    }
  }
  
  $rc;
  
}



sub retrieve {
  my ($self, $myconfig, $form) = @_;
  
  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query;
  my $sth;
  my $var;
  my $ref;

  $query = qq|SELECT curr, current_date
              FROM defaults|;
  ($form->{currencies}, $form->{transdate}) = $dbh->selectrow_array($query);
  
  if ($form->{id}) {
    
    # retrieve order
    $query = qq|SELECT o.ordnumber, o.transdate, o.reqdate, o.terms,
                o.taxincluded, o.shippingpoint, o.shipvia, o.notes, o.intnotes,
		o.curr AS currency, e.name AS employee, o.employee_id,
		o.$form->{vc}_id, vc.name AS $form->{vc}, o.amount AS invtotal,
		o.closed, o.reqdate, o.quonumber, o.department_id,
		d.description AS department, o.language_code, o.ponumber
		FROM oe o
	        JOIN $form->{vc} vc ON (o.$form->{vc}_id = vc.id)
	        LEFT JOIN employee e ON (o.employee_id = e.id)
	        LEFT JOIN department d ON (o.department_id = d.id)
		WHERE o.id = $form->{id}|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    $ref = $sth->fetchrow_hashref(NAME_lc);
    for (keys %$ref) { $form->{$_} = $ref->{$_} }
    $sth->finish;
   
    $query = qq|SELECT * FROM shipto
                WHERE trans_id = $form->{id}|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    $ref = $sth->fetchrow_hashref(NAME_lc);
    for (keys %$ref) { $form->{$_} = $ref->{$_} }
    $sth->finish;

    # get printed, emailed and queued
    $query = qq|SELECT s.printed, s.emailed, s.spoolfile, s.formname
                FROM status s
		WHERE s.trans_id = $form->{id}|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      $form->{printed} .= "$ref->{formname} " if $ref->{printed};
      $form->{emailed} .= "$ref->{formname} " if $ref->{emailed};
      $form->{queued} .= "$ref->{formname} $ref->{spoolfile} " if $ref->{spoolfile};
    }
    $sth->finish;
    for (qw(printed emailed queued)) { $form->{$_} =~ s/ +$//g }

    my %oid = ( 'Pg'		=> 'oid',
                'PgPP'		=> 'oid',
                'Oracle'	=> 'rowid',
		'DB2'		=> '1=1'
	      );

    # retrieve individual items
    $query = qq|SELECT o.id AS orderitems_id,
                p.partnumber, p.assembly, o.description, o.qty,
		o.sellprice, o.parts_id AS id, o.unit, o.discount, p.bin,
                o.reqdate, o.project_id, o.serialnumber, o.ship,
		pr.projectnumber,
		pg.partsgroup, p.partsgroup_id, p.partnumber AS sku,
		p.listprice, p.lastcost, p.weight, p.onhand,
		p.inventory_accno_id, p.income_accno_id, p.expense_accno_id,
		t.description AS partsgrouptranslation
		FROM orderitems o
		JOIN parts p ON (o.parts_id = p.id)
		LEFT JOIN project pr ON (o.project_id = pr.id)
		LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
		LEFT JOIN translation t ON (t.trans_id = p.partsgroup_id AND t.language_code = '$form->{language_code}')
		WHERE o.trans_id = $form->{id}
                ORDER BY o.$oid{$myconfig->{dbdriver}}|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    # foreign exchange rates
    &exchangerate_defaults($dbh, $form);

    # query for price matrix
    my $pmh = &price_matrix_query($dbh, $form);
    
    # taxes
    $query = qq|SELECT c.accno
		FROM chart c
		JOIN partstax pt ON (pt.chart_id = c.id)
		WHERE pt.parts_id = ?|;
    my $tth = $dbh->prepare($query) || $form->dberror($query);
   
    my $taxrate;
    my $ptref;
    my $sellprice;
    my $listprice;
    
    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {

      ($decimalplaces) = ($ref->{sellprice} =~ /\.(\d+)/);
      $decimalplaces = length $decimalplaces;
      $decimalplaces = ($decimalplaces > 2) ? $decimalplaces : 2;

      $tth->execute($ref->{id});
      $ref->{taxaccounts} = "";
      $taxrate = 0;
      
      while ($ptref = $tth->fetchrow_hashref(NAME_lc)) {
        $ref->{taxaccounts} .= "$ptref->{accno} ";
        $taxrate += $form->{"$ptref->{accno}_rate"};
      }
      $tth->finish;
      chop $ref->{taxaccounts};

      # preserve prices
      $sellprice = $ref->{sellprice};
      $listprice = $ref->{listprice};
      
      # multiply by exchangerate
      for (qw(sellprice listprice)) { $ref->{$_} = $form->round_amount($ref->{$_} * $form->{$form->{currency}}, $decimalplaces) }
      
      # partnumber and price matrix
      &price_matrix($pmh, $ref, $form->{transdate}, $decimalplaces, $form, $myconfig);

      $ref->{sellprice} = $sellprice;
      $ref->{listprice} = $listprice;

      $ref->{partsgroup} = $ref->{partsgrouptranslation} if $ref->{partsgrouptranslation};
      
      push @{ $form->{form_details} }, $ref;
      
    }
    $sth->finish;

    # get recurring transaction
    $form->get_recurring($dbh);

  } else {

    # get last name used
    $form->lastname_used($myconfig, $dbh, $form->{vc}) unless $form->{"$form->{vc}_id"};
    delete $form->{notes};

  }

  $dbh->disconnect;

}


sub price_matrix_query {
  my ($dbh, $form) = @_;

  my $query;
  my $sth;

  if ($form->{customer_id}) {
    $query = qq|SELECT p.id AS parts_id, 0 AS customer_id, 0 AS pricegroup_id,
             0 AS pricebreak, p.sellprice, NULL AS validfrom, NULL AS validto,
	     '$form->{defaultcurrency}' AS curr, '' AS pricegroup
	     FROM parts p
	     WHERE p.id = ?

	     UNION
    
             SELECT p.*, g.pricegroup
             FROM partscustomer p
	     LEFT JOIN pricegroup g ON (g.id = p.pricegroup_id)
	     WHERE p.parts_id = ?
	     AND p.customer_id = $form->{customer_id}

	     UNION

	     SELECT p.*, g.pricegroup
	     FROM partscustomer p
	     LEFT JOIN pricegroup g ON (g.id = p.pricegroup_id)
	     JOIN customer c ON (c.pricegroup_id = g.id)
	     WHERE p.parts_id = ?
	     AND c.id = $form->{customer_id}

	     UNION

	     SELECT p.*, '' AS pricegroup
	     FROM partscustomer p
	     WHERE p.customer_id = 0
	     AND p.pricegroup_id = 0
	     AND p.parts_id = ?

	     ORDER BY customer_id DESC, pricegroup_id DESC, pricebreak
	     |;
    $sth = $dbh->prepare($query) || $form->dberror($query);
  }
  
  if ($form->{vendor_id}) {
    # price matrix and vendor's partnumber
    $query = qq|SELECT partnumber
		FROM partsvendor
		WHERE parts_id = ?
		AND vendor_id = $form->{vendor_id}|;
    $sth = $dbh->prepare($query) || $form->dberror($query);
  }
  
  $sth;

}


sub price_matrix {
  my ($pmh, $ref, $transdate, $decimalplaces, $form, $myconfig) = @_;

  $ref->{pricematrix} = "";
  my $customerprice;
  my $pricegroupprice;
  my $sellprice;
  my $mref;
  my %p = ();
  
  # depends if this is a customer or vendor
  if ($form->{customer_id}) {
    $pmh->execute($ref->{id}, $ref->{id}, $ref->{id}, $ref->{id});

    while ($mref = $pmh->fetchrow_hashref(NAME_lc)) {

      # check date
      if ($mref->{validfrom}) {
	next if $transdate < $form->datetonum($myconfig, $mref->{validfrom});
      }
      if ($mref->{validto}) {
	next if $transdate > $form->datetonum($myconfig, $mref->{validto});
      }

      # convert price
      $sellprice = $form->round_amount($mref->{sellprice} * $form->{$mref->{curr}}, $decimalplaces);
      
      if ($mref->{customer_id}) {
	$ref->{sellprice} = $sellprice if !$mref->{pricebreak};
	$p{$mref->{pricebreak}} = $sellprice;
	$customerprice = 1;
      }

      if ($mref->{pricegroup_id}) {
	if (! $customerprice) {
	  $ref->{sellprice} = $sellprice if !$mref->{pricebreak};
	  $p{$mref->{pricebreak}} = $sellprice;
	}
	$pricegroupprice = 1;
      }

      if (!$customerprice && !$pricegroupprice) {
	$p{$mref->{pricebreak}} = $sellprice;
      }

    }
    $pmh->finish;

    if (%p) {
      if ($ref->{sellprice}) {
	$p{0} = $ref->{sellprice};
      }
      for (sort { $a <=> $b } keys %p) { $ref->{pricematrix} .= "${_}:$p{$_} " }
    } else {
      if ($init) {
	$ref->{sellprice} = $form->round_amount($ref->{sellprice}, $decimalplaces);
      } else {
	$ref->{sellprice} = $form->round_amount($ref->{sellprice} * (1 - $form->{tradediscount}), $decimalplaces);
      }
      $ref->{pricematrix} = "0:$ref->{sellprice} " if $ref->{sellprice};
    }
    chop $ref->{pricematrix};

  }


  if ($form->{vendor_id}) {
    $pmh->execute($ref->{id});
    
    $mref = $pmh->fetchrow_hashref(NAME_lc);

    if ($mref->{partnumber} ne "") {
      $ref->{partnumber} = $mref->{partnumber};
    }

    if ($mref->{lastcost}) {
      # do a conversion
      $ref->{sellprice} = $form->round_amount($mref->{lastcost} * $form->{$mref->{curr}}, $decimalplaces);
    }
    $pmh->finish;

    $ref->{sellprice} *= 1;

    # add 0:price to matrix
    $ref->{pricematrix} = "0:$ref->{sellprice}";

  }

}


sub exchangerate_defaults {
  my ($dbh, $form) = @_;

  my $var;
  my $buysell = ($form->{vc} eq "customer") ? "buy" : "sell";
  
  # get default currencies
  my $query = qq|SELECT substr(curr,1,3), curr FROM defaults|;
  ($form->{defaultcurrency}, $form->{currencies}) = $dbh->selectrow_array($query);

  $query = qq|SELECT $buysell
              FROM exchangerate
	      WHERE curr = ?
	      AND transdate = ?|;
  my $eth1 = $dbh->prepare($query) || $form->dberror($query);
  $query = qq~SELECT max(transdate || ' ' || $buysell || ' ' || curr)
              FROM exchangerate
	      WHERE curr = ?~;
  my $eth2 = $dbh->prepare($query) || $form->dberror($query);

  # get exchange rates for transdate or max
  foreach $var (split /:/, substr($form->{currencies},4)) {
    $eth1->execute($var, $form->{transdate});
    ($form->{$var}) = $eth1->fetchrow_array;
    if (! $form->{$var} ) {
      $eth2->execute($var);
      
      ($form->{$var}) = $eth2->fetchrow_array;
      ($null, $form->{$var}) = split / /, $form->{$var};
      $form->{$var} = 1 unless $form->{$var};
      $eth2->finish;
    }
    $eth1->finish;
  }

  $form->{$form->{defaultcurrency}} = 1;
      
}


sub order_details {
  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  my $query;
  my $sth;
    
  my $item;
  my $i;
  my @sortlist = ();
  my $projectnumber;
  my $projectnumber_id;
  my $translation;
  my $partsgroup;

  my %oid = ( 'Pg'	=> 'oid',
              'PgPP'	=> 'oid',
              'Oracle'	=> 'rowid',
	      'DB2'	=> '1=1'
	    );
  
  # sort items by project and partsgroup
  for $i (1 .. $form->{rowcount}) {
    $projectnumber = "";
    $partsgroup = "";
    $projectnumber_id = 0;
    if (($form->{"projectnumber_$i"} ne "") && $form->{groupprojectnumber}) {
      ($projectnumber, $projectnumber_id) = split /--/, $form->{"projectnumber_$i"};
    }
    if (($form->{"partsgroup_$i"} ne "") && $form->{grouppartsgroup}) {
      ($partsgroup) = split /--/, $form->{"partsgroup_$i"};
    }
    push @sortlist, [ $i, "$projectnumber$partsgroup", $projectnumber, $projectnumber_id, $partsgroup ];
    
  }

  # sort the whole thing by project and group
  @sortlist = sort { $a->[1] cmp $b->[1] } @sortlist;

  # if there is a warehouse limit picking
  if ($form->{warehouse_id} && $form->{formname} =~ /(pick|packing)_list/) {
    # run query to check for inventory
    $query = qq|SELECT sum(qty) AS qty
                FROM inventory
		WHERE parts_id = ?
		AND warehouse_id = ?|;
    $sth = $dbh->prepare($query) || $form->dberror($query);

    for $i (1 .. $form->{rowcount}) {
      $sth->execute($form->{"id_$i"}, $form->{warehouse_id}) || $form->dberror;

      ($qty) = $sth->fetchrow_array;
      $sth->finish;

      $form->{"qty_$i"} = 0 if $qty == 0;
      
      if ($form->parse_amount($myconfig, $form->{"ship_$i"}) > $qty) {
	$form->{"ship_$i"} = $form->format_amount($myconfig, $qty);
      }
    }
  }
    
  my @taxaccounts;
  my %taxaccounts;
  my $taxrate;
  my $taxamount;
  my $taxbase;
  my $taxdiff;
 
  $query = qq|SELECT p.description, t.description
              FROM project p
	      LEFT JOIN translation t ON (t.trans_id = p.id AND t.language_code = '$form->{language_code}')
	      WHERE id = ?|;
  my $prh = $dbh->prepare($query) || $form->dberror($query);

  my $runningnumber = 1;
  my $sameitem = "";
  my $subtotal;
  my $k = scalar @sortlist;
  my $j = 0;

  $query = qq|SELECT assembly, weight FROM parts 
              WHERE id = ?|; 
  my $pth = $dbh->prepare($query) || $form->dberror($query);
  
  foreach $item (@sortlist) {
    $i = $item->[0];
    $j++;

    if ($form->{groupprojectnumber} || $form->{grouppartsgroup}) {
      if ($item->[1] ne $sameitem) {

        $projectnumber = "";
	if ($form->{groupprojectnumber} && $item->[2]) {
	  # get project description
	  $prh->execute($item->[3]) || $form->dberror($query);

	  ($projectnumber, $translation) = $prh->fetchrow_array;
	  $prh->finish;

	  $projectnumber = ($translation) ? "$item->[2], $translation" : "$item->[2], $projectnumber";
	}
	  
	if ($form->{grouppartsgroup} && $item->[4]) {
	  $projectnumber .= " / " if $projectnumber;
	  $projectnumber .= $item->[4];
	}
	
	$form->{projectnumber} = $projectnumber;
	$form->format_string(projectnumber);
	
	push(@{ $form->{description} }, qq|$form->{projectnumber}|);
	$sameitem = $item->[1];

	for (qw(runningnumber number sku qty ship unit bin serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate linetotal weight)) { push(@{ $form->{$_} }, "") }
      }
    }

    $form->{"qty_$i"} = $form->parse_amount($myconfig, $form->{"qty_$i"});
    $form->{"ship_$i"} = $form->parse_amount($myconfig, $form->{"ship_$i"});
    
    if ($form->{"qty_$i"}) {

      $pth->execute($form->{"id_$i"});
      $ref = $pth->fetchrow_hashref(NAME_lc);
      for (keys %$ref) { $form->{"${_}_$i"} = $ref->{$_} }
      $pth->finish;
      
      $form->{totalqty} += $form->{"qty_$i"};
      $form->{totalship} += $form->{"ship_$i"};
      $form->{totalweight} += ($form->{"weight_$i"} * $form->{"qty_$i"});
      $form->{totalweightship} += ($form->{"weight_$i"} * $form->{"ship_$i"});

      # add number, description and qty to $form->{number}, ....
      push(@{ $form->{runningnumber} }, $runningnumber++);
      push(@{ $form->{number} }, qq|$form->{"partnumber_$i"}|);
      push(@{ $form->{sku} }, qq|$form->{"sku_$i"}|);
      push(@{ $form->{description} }, qq|$form->{"description_$i"}|);
      push(@{ $form->{qty} }, $form->format_amount($myconfig, $form->{"qty_$i"}));
      push(@{ $form->{ship} }, $form->format_amount($myconfig, $form->{"ship_$i"}));
      push(@{ $form->{unit} }, qq|$form->{"unit_$i"}|);
      push(@{ $form->{bin} }, qq|$form->{"bin_$i"}|);
      push(@{ $form->{serialnumber} }, qq|$form->{"serialnumber_$i"}|);
      push(@{ $form->{reqdate} }, qq|$form->{"reqdate_$i"}|);
      push(@{ $form->{projectnumber} }, qq|$form->{"projectnumber_$i"}|);
      
      push(@{ $form->{sellprice} }, $form->{"sellprice_$i"});
 
      push(@{ $form->{listprice} }, $form->{"listprice_$i"});
      
      push(@{ $form->{weight} }, $form->format_amount($myconfig, $form->{"weight_$i"} * $form->{"ship_$i"}));

      my $sellprice = $form->parse_amount($myconfig, $form->{"sellprice_$i"});
      my ($dec) = ($sellprice =~ /\.(\d+)/);
      $dec = length $dec;
      my $decimalplaces = ($dec > 2) ? $dec : 2;
      
      my $discount = $form->round_amount($sellprice * $form->parse_amount($myconfig, $form->{"discount_$i"}) / 100, $decimalplaces);

      # keep a netprice as well, (sellprice - discount)
      $form->{"netprice_$i"} = $sellprice - $discount;

      my $linetotal = $form->round_amount($form->{"qty_$i"} * $form->{"netprice_$i"}, 2);

      push(@{ $form->{netprice} }, ($form->{"netprice_$i"}) ? $form->format_amount($myconfig, $form->{"netprice_$i"}, $decimalplaces) : " ");
      
      $discount = ($discount) ? $form->format_amount($myconfig, $discount * -1, $decimalplaces) : " ";
      $linetotal = ($linetotal) ? $linetotal : " ";

      push(@{ $form->{discount} }, $discount);
      push(@{ $form->{discountrate} }, $form->format_amount($myconfig, $form->{"discount_$i"}));
      
      $form->{ordtotal} += $linetotal;

      # this is for the subtotals for grouping
      $subtotal += $linetotal;

      push(@{ $form->{linetotal} }, $form->format_amount($myconfig, $linetotal, 2));
      
      @taxaccounts = split / /, $form->{"taxaccounts_$i"};

      my $ml = 1;
      for (0 .. 1) {
	  
	$taxrate = 0;
	for (@taxaccounts) { $taxrate += $form->{"${_}_rate"} if ($form->{"${_}_rate"} * $ml) > 0 }
	$taxrate *= $ml;
	$taxamount = $linetotal * $taxrate / (1 + $taxrate);
	$taxbase = ($linetotal - $taxamount);
	
	foreach $item (@taxaccounts) {
	  if (($form->{"${item}_rate"} * $ml) > 0) {
	    if ($form->{taxincluded}) {
	      $taxaccounts{$item} += $linetotal * $form->{"${item}_rate"} / (1 + $taxrate);
	      $taxbase{$item} += $taxbase;
	    } else {
	      $taxbase{$item} += $linetotal;
	      $taxaccounts{$item} += $linetotal * $form->{"${item}_rate"};
	    }
	  }
	}
	$ml *= -1;
      }
	
      if ($form->{"assembly_$i"}) {
	$form->{stagger} = -1;
	&assembly_details($myconfig, $form, $dbh, $form->{"id_$i"}, $oid{$myconfig->{dbdriver}}, $form->{"qty_$i"});
      }

    }

    # add subtotal
    if ($form->{groupprojectnumber} || $form->{grouppartsgroup}) {
      if ($subtotal) {
	if ($j < $k) {
	  # look at next item
	  if ($sortlist[$j]->[1] ne $sameitem) {

	    for (qw(runningnumber number sku qty ship unit bin serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate weight)) { push(@{ $form->{$_} }, "") }

	    push(@{ $form->{description} }, $form->{groupsubtotaldescription});

            if ($form->{groupsubtotaldescription} ne "") {
	      push(@{ $form->{linetotal} }, $form->format_amount($myconfig, $subtotal, 2));
	    } else {
	      push(@{ $form->{linetotal} }, "");
	    }

	    $subtotal = 0;
	  }

	} else {

	  # got last item
          if ($form->{groupsubtotaldescription} ne "") {
	    
	    for (qw(runningnumber number sku qty ship unit bin serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate weight)) { push(@{ $form->{$_} }, "") }

	    push(@{ $form->{description} }, $form->{groupsubtotaldescription});
	    push(@{ $form->{linetotal} }, $form->format_amount($myconfig, $subtotal, 2));
	  }
	}
      }
    }
  }


  my $tax = 0;
  foreach $item (sort keys %taxaccounts) {
    if ($form->round_amount($taxaccounts{$item}, 2)) {
      $form->{"${item}_taxbase"} = $form->format_amount($myconfig, $taxbase{$item}, 2);
      push(@{ $form->{taxbase} }, $form->{"${item}_taxbase"});
      
      $tax += $taxamount = $form->round_amount($taxaccounts{$item}, 2);

      $form->{"${item}_tax"} = $form->format_amount($myconfig, $taxamount, 2);
      push(@{ $form->{tax} }, $form->{"${item}_tax"});
      
      push(@{ $form->{taxdescription} }, $form->{"${item}_description"});
      
      $form->{"${item}_taxrate"} = $form->format_amount($myconfig, $form->{"${item}_rate"} * 100);
      push(@{ $form->{taxrate} }, $form->{"${item}_taxrate"});
      
      push(@{ $form->{taxnumber} }, $form->{"${item}_taxnumber"});
    }
  }

  for (qw(totalqty totalship totalweight)) { $form->{$_} = $form->format_amount($myconfig, $form->{$_}) }
  $form->{subtotal} = $form->format_amount($myconfig, $form->{ordtotal}, 2);
  $form->{ordtotal} = ($form->{taxincluded}) ? $form->{ordtotal} : $form->{ordtotal} + $tax;

  use SL::CP;
  my $c;
  if ($form->{language_code} ne "") {
    $c = new CP $form->{language_code};
  } else {
    $c = new CP $myconfig->{countrycode};
  }
  $c->init;
  my $whole;
  ($whole, $form->{decimal}) = split /\./, $form->{ordtotal};
  $form->{decimal} .= "00";
  $form->{decimal} = substr($form->{decimal}, 0, 2);

  $form->{text_decimal} = $c->num2text($form->{decimal} * 1);
  $form->{text_amount} = $c->num2text($whole);
  
  # format amounts
  $form->{quototal} = $form->{ordtotal} = $form->format_amount($myconfig, $form->{ordtotal}, 2);

  $form->format_string(qw(text_amount text_decimal));

  $query = qq|SELECT weightunit FROM defaults|;
  ($form->{weightunit}) = $dbh->selectrow_array($query);
  
  $dbh->disconnect;

}


sub assembly_details {
  my ($myconfig, $form, $dbh, $id, $oid, $qty) = @_;

  my $sm = "";
  my $spacer;

  $form->{stagger}++;
  if ($form->{format} eq 'html') {
    $spacer = "&nbsp;" x (3 * ($form->{stagger} - 1)) if $form->{stagger} > 1;
  }
  if ($form->{format} =~ /(postscript|pdf)/) {
    if ($form->{stagger} > 1) {
      $spacer = ($form->{stagger} - 1) * 3;
      $spacer = '\rule{'.$spacer.'mm}{0mm}';
    }
  }

  # get parts and push them onto the stack
  my $sortorder = "";
  
  if ($form->{grouppartsgroup}) {
    $sortorder = qq|ORDER BY pg.partsgroup, a.$oid|;
  } else {
    $sortorder = qq|ORDER BY a.$oid|;
  }
  
  my $where = ($form->{formname} eq 'work_order') ? "1 = 1" : "a.bom = '1'";
  
  my $query = qq|SELECT p.partnumber, p.description, p.unit, a.qty,
	         pg.partsgroup, p.partnumber AS sku, p.assembly, p.id, p.bin
	         FROM assembly a
	         JOIN parts p ON (a.parts_id = p.id)
	         LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
	         WHERE $where
	         AND a.id = '$id'
	         $sortorder|;
  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {
   
    for (qw(partnumber description partsgroup)) {
      $form->{"a_$_"} = $ref->{$_};
      $form->format_string("a_$_");
    }
    
    if ($form->{grouppartsgroup} && $ref->{partsgroup} ne $sm) {
      for (qw(number sku unit qty runningnumber ship bin serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate linetotal)) { push(@{ $form->{$_} }, "") }
      $sm = ($form->{"a_partsgroup"}) ? $form->{"a_partsgroup"} : "";
      push(@{ $form->{description} }, "$spacer$sm");
    }
    
    if ($form->{stagger}) {
     
      push(@{ $form->{description} }, qq|$spacer$form->{"a_partnumber"}, $form->{"a_description"}|);
      for (qw(number sku runningnumber ship serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate linetotal)) { push(@{ $form->{$_} }, "") }
      
    } else {
      
      push(@{ $form->{description} }, qq|$form->{"a_description"}|);
      push(@{ $form->{sku} }, $form->{"a_partnumber"});
      push(@{ $form->{number} }, $form->{"a_partnumber"});
      
      for (qw(runningnumber ship serialnumber reqdate projectnumber sellprice listprice netprice discount discountrate linetotal)) { push(@{ $form->{$_} }, "") }
      
    }
      
    push(@{ $form->{qty} }, $form->format_amount($myconfig, $ref->{qty} * $qty));
    for (qw(unit bin)) {
      $form->{"a_$_"} = $ref->{$_};
      $form->format_string("a_$_");
      push(@{ $form->{$_} }, $form->{"a_$_"});
    }

    if ($ref->{assembly} && $form->{formname} eq 'work_order') {
      &assembly_details($myconfig, $form, $dbh, $ref->{id}, $oid, $ref->{qty} * $qty);
    }
    
  }
  $sth->finish;

  $form->{stagger}--;
  
}


sub project_description {
  my ($self, $dbh, $id) = @_;

  my $query = qq|SELECT description
                 FROM project
		 WHERE id = $id|;
  ($_) = $dbh->selectrow_array($query);
  
  $_;

}


sub get_warehouses {
  my ($self, $myconfig, $form) = @_;
  
  my $dbh = $form->dbconnect($myconfig);
  # setup warehouses
  my $query = qq|SELECT id, description
                 FROM warehouse
		 ORDER BY 2|;

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {
    push @{ $form->{all_warehouse} }, $ref;
  }
  $sth->finish;

  $dbh->disconnect;

}


sub save_inventory {
  my ($self, $myconfig, $form) = @_;
  
  my ($null, $warehouse_id) = split /--/, $form->{warehouse};
  $warehouse_id *= 1;

  my $ml = ($form->{type} eq 'ship_order') ? -1 : 1;
  
  my $dbh = $form->dbconnect_noauto($myconfig);
  my $sth;
  my $wth;
  my $serialnumber;
  my $ship;
  
  my ($null, $employee_id) = split /--/, $form->{employee};
  ($null, $employee_id) = $form->get_employee($dbh) if ! $employee_id;
 
  $query = qq|SELECT serialnumber, ship
              FROM orderitems
              WHERE trans_id = ?
	      AND id = ?
	      FOR UPDATE|;
  $sth = $dbh->prepare($query) || $form->dberror($query);

  $query = qq|SELECT sum(qty)
              FROM inventory
	      WHERE parts_id = ?
	      AND warehouse_id = ?|;
  $wth = $dbh->prepare($query) || $form->dberror($query);
  

  for my $i (1 .. $form->{rowcount}) {

    $ship = (abs($form->{"ship_$i"}) > abs($form->{"qty_$i"})) ? $form->{"qty_$i"} : $form->{"ship_$i"};
    
    if ($warehouse_id && $form->{type} eq 'ship_order') {

      $wth->execute($form->{"id_$i"}, $warehouse_id) || $form->dberror;

      ($qty) = $wth->fetchrow_array;
      $wth->finish;

      if ($ship > $qty) {
	$ship = $qty;
      }
    }

    
    if ($ship) {

      $ship *= $ml;
      $query = qq|INSERT INTO inventory (parts_id, warehouse_id,
                  qty, trans_id, orderitems_id, shippingdate, employee_id)
                  VALUES ($form->{"id_$i"}, $warehouse_id,
		  $ship, $form->{"id"},
		  $form->{"orderitems_id_$i"}, '$form->{shippingdate}',
		  $employee_id)|;
      $dbh->do($query) || $form->dberror($query);
     
      # add serialnumber, ship to orderitems
      $sth->execute($form->{id}, $form->{"orderitems_id_$i"}) || $form->dberror;
      ($serialnumber, $ship) = $sth->fetchrow_array;
      $sth->finish;

      $serialnumber .= " " if $serialnumber;
      $serialnumber .= qq|$form->{"serialnumber_$i"}|;
      $ship += $form->{"ship_$i"};

      $query = qq|UPDATE orderitems SET
                  serialnumber = '$serialnumber',
		  ship = $ship,
		  reqdate = '$form->{shippingdate}'
		  WHERE trans_id = $form->{id}
		  AND id = $form->{"orderitems_id_$i"}|;
      $dbh->do($query) || $form->dberror($query);
      
      # update order with ship via
      $query = qq|UPDATE oe SET
                  shippingpoint = |.$dbh->quote($form->{shippingpoint}).qq|,
                  shipvia = |.$dbh->quote($form->{shipvia}).qq|
		  WHERE id = $form->{id}|;
      $dbh->do($query) || $form->dberror($query);
		  
      # update onhand for parts
      $form->update_balance($dbh,
                            "parts",
                            "onhand",
                            qq|id = $form->{"id_$i"}|,
                            $form->{"ship_$i"} * $ml);

    }
  }

  my $rc = $dbh->commit;
  $dbh->disconnect;

  $rc;

}


sub adj_onhand {
  my ($dbh, $form, $ml) = @_;

  my $query = qq|SELECT oi.parts_id, oi.ship, p.inventory_accno_id, p.assembly
                 FROM orderitems oi
		 JOIN parts p ON (p.id = oi.parts_id)
                 WHERE oi.trans_id = $form->{id}|;
  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $query = qq|SELECT sum(p.inventory_accno_id)
	      FROM parts p
	      JOIN assembly a ON (a.parts_id = p.id)
	      WHERE a.id = ?|;
  my $ath = $dbh->prepare($query) || $form->dberror($query);

  my $ispa;
  my $ref;
  
  while ($ref = $sth->fetchrow_hashref(NAME_lc)) {

    if ($ref->{inventory_accno_id} || $ref->{assembly}) {

      # do not update if assembly consists of all services
      if ($ref->{assembly}) {
	$ath->execute($ref->{parts_id}) || $form->dberror($query);

        ($ispa) = $ath->fetchrow_array;
	$ath->finish;

	next unless $ispa;
	
      }

      # adjust onhand in parts table
      $form->update_balance($dbh,
			    "parts",
			    "onhand",
			    qq|id = $ref->{parts_id}|,
			    $ref->{ship} * $ml);
    }
  }
  
  $sth->finish;

}


sub adj_inventory {
  my ($dbh, $myconfig, $form) = @_;

  my %oid = ( 'Pg'	=> 'oid',
              'PgPP'	=> 'oid',
              'Oracle'	=> 'rowid',
	      'DB2'	=> '1=1'
	    );
  
  # increase/reduce qty in inventory table
  my $query = qq|SELECT oi.id, oi.parts_id, oi.ship
                 FROM orderitems oi
                 WHERE oi.trans_id = $form->{id}|;
  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);

  $query = qq|SELECT $oid{$myconfig->{dbdriver}} AS oid, qty,
                     (SELECT SUM(qty) FROM inventory
                      WHERE trans_id = $form->{id}
		      AND orderitems_id = ?) AS total
	      FROM inventory
              WHERE trans_id = $form->{id}
	      AND orderitems_id = ?|;
  my $ith = $dbh->prepare($query) || $form->dberror($query);
  
  my $qty;
  my $ml = ($form->{type} =~ /(ship|sales)_order/) ? -1 : 1;
  
  while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {

    $ith->execute($ref->{id}, $ref->{id}) || $form->dberror($query);

    while (my $inv = $ith->fetchrow_hashref(NAME_lc)) {

      if (($qty = (($inv->{total} * $ml) - $ref->{ship})) >= 0) {
	$qty = $inv->{qty} if ($qty > ($inv->{qty} * $ml));
	
	$form->update_balance($dbh,
                              "inventory",
                              "qty",
                              qq|$oid{$myconfig->{dbdriver}} = $inv->{oid}|,
                              $qty * -1 * $ml);
      }
    }
    $ith->finish;

  }
  $sth->finish;

  # delete inventory entries if qty = 0
  $query = qq|DELETE FROM inventory
              WHERE trans_id = $form->{id}
	      AND qty = 0|;
  $dbh->do($query) || $form->dberror($query);

}


sub get_inventory {
  my ($self, $myconfig, $form) = @_;

  my $where;
  my $query;
  my $null;
  my $fromwarehouse_id;
  my $towarehouse_id;
  my $var;
  
  my $dbh = $form->dbconnect($myconfig);
  
  if ($form->{partnumber} ne "") {
    $var = $form->like(lc $form->{partnumber});
    $where .= "
                AND lower(p.partnumber) LIKE '$var'";
  }
  if ($form->{description} ne "") {
    $var = $form->like(lc $form->{description});
    $where .= "
                AND lower(p.description) LIKE '$var'";
  }
  if ($form->{partsgroup} ne "") {
    ($null, $var) = split /--/, $form->{partsgroup};
    $where .= "
                AND pg.id = $var";
  }


  ($null, $fromwarehouse_id) = split /--/, $form->{fromwarehouse};
  $fromwarehouse_id *= 1;
  
  ($null, $towarehouse_id) = split /--/, $form->{towarehouse};
  $towarehouse_id *= 1;

  my %ordinal = ( partnumber => 2,
                  description => 3,
		  partsgroup => 5,
		  warehouse => 6,
		);

  my @a = (partnumber, warehouse);
  my $sortorder = $form->sort_order(\@a, \%ordinal);
  
  if ($fromwarehouse_id) {
    if ($towarehouse_id) {
      $where .= "
                AND NOT i.warehouse_id = $towarehouse_id";
    }
    $query = qq|SELECT p.id, p.partnumber, p.description,
                sum(i.qty) * 2 AS onhand, sum(i.qty) AS qty,
		pg.partsgroup, w.description AS warehouse, i.warehouse_id
		FROM inventory i
		JOIN parts p ON (p.id = i.parts_id)
		LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
		JOIN warehouse w ON (w.id = i.warehouse_id)
		WHERE i.warehouse_id = $fromwarehouse_id
		$where
		GROUP BY p.id, p.partnumber, p.description, pg.partsgroup, w.description, i.warehouse_id 
		ORDER BY $sortorder|;
  } else {
    if ($towarehouse_id) {
      $query = qq|
 	      SELECT p.id, p.partnumber, p.description,
	      p.onhand, (SELECT SUM(qty) FROM inventory i WHERE i.parts_id = p.id) AS qty,
              pg.partsgroup, '' AS warehouse, 0 AS warehouse_id
              FROM parts p
	      LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
	      WHERE p.onhand > 0
	      $where
	  UNION|;
    }

    $query .= qq|
              SELECT p.id, p.partnumber, p.description,
	      sum(i.qty) * 2 AS onhand, sum(i.qty) AS qty,
	      pg.partsgroup, w.description AS warehouse, i.warehouse_id
	      FROM inventory i
	      JOIN parts p ON (p.id = i.parts_id)
	      LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id)
	      JOIN warehouse w ON (w.id = i.warehouse_id)
	      WHERE i.warehouse_id != $towarehouse_id
	      $where
	      GROUP BY p.id, p.partnumber, p.description, pg.partsgroup, w.description, i.warehouse_id
	      ORDER BY $sortorder|;
  }

  my $sth = $dbh->prepare($query);
  $sth->execute || $form->dberror($query);
  
  while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
    $ref->{qty} = $ref->{onhand} - $ref->{qty};
    push @{ $form->{all_inventory} }, $ref if $ref->{qty} > 0;
  }
  $sth->finish;

  $dbh->disconnect;

}


sub transfer {
  my ($self, $myconfig, $form) = @_;
  
  my $dbh = $form->dbconnect_noauto($myconfig);
  
  ($form->{employee}, $form->{employee_id}) = $form->get_employee($dbh);
  
  my @a = localtime;
  $a[5] += 1900;
  $a[4]++;
  $a[4] = substr("0$a[4]", -2);
  $a[3] = substr("0$a[3]", -2);
  $shippingdate = "$a[5]$a[4]$a[3]";

  my %total = ();

  my $query = qq|INSERT INTO inventory
                 (warehouse_id, parts_id, qty, shippingdate, employee_id)
		 VALUES (?, ?, ?, '$shippingdate', $form->{employee_id})|;
  $sth = $dbh->prepare($query) || $form->dberror($query);

  my $qty;
  
  for my $i (1 .. $form->{rowcount}) {
    $qty = $form->parse_amount($myconfig, $form->{"transfer_$i"});

    $qty = $form->{"qty_$i"} if ($qty > $form->{"qty_$i"});

    if ($qty > 0) {
      # to warehouse
      if ($form->{warehouse_id}) {
	$sth->execute($form->{warehouse_id}, $form->{"id_$i"}, $qty) || $form->dberror;
	$sth->finish;
      }
      
      # from warehouse
      if ($form->{"warehouse_id_$i"}) {
	$sth->execute($form->{"warehouse_id_$i"}, $form->{"id_$i"}, $qty * -1) || $form->dberror;
	$sth->finish;
      }
    }
  }

  my $rc = $dbh->commit;
  $dbh->disconnect;

  $rc;

}


sub get_soparts {
  my ($self, $myconfig, $form) = @_;
  
  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  
  my $id;
  my $ref;
  
  # store required items from selected sales orders
  my $query = qq|SELECT p.id, oi.qty - oi.ship AS required,
                 p.assembly
                 FROM orderitems oi
	         JOIN parts p ON (p.id = oi.parts_id)
	         WHERE oi.trans_id = ?|;
  my $sth = $dbh->prepare($query) || $form->dberror($query);
  
  for (my $i = 1; $i <= $form->{rowcount}; $i++) {

    if ($form->{"ndx_$i"}) {

      $sth->execute($form->{"ndx_$i"});
      
      while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
	&add_items_required("", $dbh, $form, $ref->{id}, $ref->{required}, $ref->{assembly});
      }
      $sth->finish;
    }

  }

  $query = qq|SELECT current_date FROM defaults|;
  ($form->{transdate}) = $dbh->selectrow_array($query);
  
  # foreign exchange rates
  &exchangerate_defaults($dbh, $form);

  $dbh->disconnect;

}


sub add_items_required {
  my ($self, $dbh, $form, $parts_id, $required, $assembly) = @_;
  
  my $query;
  my $sth;
  my $ref;

  if ($assembly) {
    $query = qq|SELECT p.id, a.qty, p.assembly
                FROM assembly a
		JOIN parts p ON (p.id = a.parts_id)
		WHERE a.id = $parts_id|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);
    
    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      &add_items_required("", $dbh, $form, $ref->{id}, $required * $ref->{qty}, $ref->{assembly});
    }
    $sth->finish;
    
  } else {

    $query = qq|SELECT partnumber, description, lastcost
		FROM parts
		WHERE id = $parts_id|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);
    $ref = $sth->fetchrow_hashref(NAME_lc);
    for (keys %$ref) { $form->{orderitems}{$parts_id}{$_} = $ref->{$_} }
    $sth->finish;

    $form->{orderitems}{$parts_id}{required} += $required;

    $query = qq|SELECT pv.partnumber, pv.leadtime, pv.lastcost, pv.curr,
		pv.vendor_id, v.name
		FROM partsvendor pv
		JOIN vendor v ON (v.id = pv.vendor_id)
		WHERE pv.parts_id = ?|;
    $sth = $dbh->prepare($query) || $form->dberror($query);

    # get cost and vendor
    $sth->execute($parts_id);

    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      for (keys %$ref) { $form->{orderitems}{$parts_id}{partsvendor}{$ref->{vendor_id}}{$_} = $ref->{$_} }
    }
    $sth->finish;
    
  }

}


sub generate_orders {
  my ($self, $myconfig, $form) = @_;

  my $i;
  my %a;
  my $query;
  my $sth;
  
  for ($i = 1; $i <= $form->{rowcount}; $i++) {
    for (qw(qty lastcost)) { $form->{"${_}_$i"} = $form->parse_amount($myconfig, $form->{"${_}_$i"}) }
    
    if ($form->{"qty_$i"}) {
      ($vendor, $vendor_id) = split /--/, $form->{"vendor_$i"};
      if ($vendor_id) {
	$a{$vendor_id}{$form->{"id_$i"}}{qty} += $form->{"qty_$i"};
	for (qw(curr lastcost)) { $a{$vendor_id}{$form->{"id_$i"}}{$_} = $form->{"${_}_$i"} }
      }
    }
  }

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);
  
  # foreign exchange rates
  &exchangerate_defaults($dbh, $form);

  my $amount;
  my $netamount;
  my $curr = "";
  my %tax;
  my $taxincluded = 0;
  my $vendor_id;

  my $description;
  my $unit;
  
  foreach $vendor_id (keys %a) {
    
    %tax = ();
    
    $query = qq|SELECT v.curr, v.taxincluded, t.rate, c.accno
                FROM vendor v
		LEFT JOIN vendortax vt ON (v.id = vt.vendor_id)
		LEFT JOIN tax t ON (t.chart_id = vt.chart_id)
		LEFT JOIN chart c ON (c.id = t.chart_id)
                WHERE v.id = $vendor_id|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);
    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      $curr = $ref->{curr};
      $taxincluded = $ref->{taxincluded};
      $tax{$ref->{accno}} = $ref->{rate};
    }
    $sth->finish;  

    $curr ||= $form->{defaultcurrency};
    $taxincluded *= 1;
    
    my $uid = time;
    $uid .= $$;
 
    $query = qq|INSERT INTO oe (ordnumber)
		VALUES ('$uid')|;
    $dbh->do($query) || $form->dberror($query);
   
    $query = qq|SELECT id FROM oe
                WHERE ordnumber = '$uid'|;
    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);
    my ($id) = $sth->fetchrow_array;
    $sth->finish;

    $amount = 0;
    $netamount = 0;
    
    foreach my $parts_id (keys %{ $a{$vendor_id} }) {

      my $sellprice = $form->round_amount($a{$vendor_id}{$parts_id}{lastcost} / $form->{$curr} * $form->{$a{$vendor_id}{$parts_id}{curr}}, 2);
      
      my $linetotal = $form->round_amount($sellprice * $a{$vendor_id}{$parts_id}{qty}, 2);
       
      $query = qq|SELECT p.description, p.unit, c.accno FROM parts p
                  LEFT JOIN partstax pt ON (p.id = pt.parts_id)
		  LEFT JOIN chart c ON (c.id = pt.chart_id)
		  WHERE p.id = $parts_id|;
      $sth = $dbh->prepare($query);
      $sth->execute || $form->dberror($query);
      
      my $rate = 0;
      while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
	$description = $ref->{description};
	$unit = $ref->{unit};
	$rate += $tax{$ref->{accno}};
      }
      $sth->finish;  

      $netamount += $linetotal;
      if ($taxincluded) {
	$amount += $linetotal;
      } else {
	$amount += $form->round_amount($linetotal * (1 + $rate), 2);
      }
	
      $description = $dbh->quote($description);
      $unit = $dbh->quote($unit);
      
      $query = qq|INSERT INTO orderitems (trans_id, parts_id, description,
                  qty, ship, sellprice, unit) VALUES
		  ($id, $parts_id, $description,
		  $a{$vendor_id}{$parts_id}{qty}, 0, $sellprice, $unit)|;
      $dbh->do($query) || $form->dberror($query);

    }

    my $ordnumber = $form->update_defaults($myconfig, 'ponumber');

    my $null;
    my $employee_id;
    my $department_id;
    
    ($null, $employee_id) = $form->get_employee($dbh);
    ($null, $department_id) = split /--/, $form->{department};
    $department_id *= 1;
    
    $query = qq|UPDATE oe SET
		ordnumber = |.$dbh->quote($ordnumber).qq|,
		transdate = current_date,
		vendor_id = $vendor_id,
		customer_id = 0,
		amount = $amount,
		netamount = $netamount,
		taxincluded = '$taxincluded',
		curr = '$curr',
		employee_id = $employee_id,
		department_id = '$department_id'
		WHERE id = $id|;
    $dbh->do($query) || $form->dberror($query);
    
  }

  my $rc = $dbh->commit;
  $dbh->disconnect;

  $rc;
  
}


1;

