CREATE TABLESPACE part1 DATAFILE '_PATH_/part1.dbf' SIZE 100M REUSE;
CREATE TABLESPACE part2 DATAFILE '_PATH_/part2.dbf' SIZE 100M REUSE;
CREATE TABLESPACE part3 DATAFILE '_PATH_/part3.dbf' SIZE 100M REUSE;
CREATE TABLESPACE part4 DATAFILE '_PATH_/part4.dbf' SIZE 100M REUSE;
CREATE TABLE sales ( invoice_no NUMBER(10), sale_date DATE NOT NULL ) PARTITION BY RANGE (sale_date)( PARTITION sales_yr1 VALUES LESS THAN (TO_DATE('01-JAN-2000','DD-MON-YYYY')) TABLESPACE part1, PARTITION sales_yr2 VALUES LESS THAN (TO_DATE('01-JAN-2001','DD-MON-YYYY')) TABLESPACE part2, PARTITION sales_yr3 VALUES LESS THAN (MAXVALUE) TABLESPACE part3);
declare
i number(10);
sql_stmt varchar2(1000);
begin
i:=0;
while ( i < 100000 ) loop
insert into sales values(01,'28-NOV-1995');
insert into sales values(02,'28-nov-2001');
insert into sales values(03,'28-JUN-2004');
i:=i+1;
end loop;
commit;
end;
/
