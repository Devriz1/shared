if object_id('spGetCollections') is not null drop proc spGetCollections

go

create proc spGetCollections
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesManID int=0,
@PropertyFilter nvarchar(max)=null,
@WOC bit=null, --w/o cheque,
@UserID int=null,
@CostCentreId int=0

as
---------------

set transaction isolation level read uncommitted

declare @Account table(ID int,Name nvarchar(100),SalesmanId int,Salesman nvarchar(100))


if nullif(@UserID,0) is not null
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c 
	join invUserCompany uc on c.CompanyID=uc.CompanyID and uc.UserID=@UserID
	left join invSalesman s on c.SalesmanId=s.Id 
	where (c.CompanyId=@CompanyId or @CompanyId=0)
	and (c.SalesmanId=@SalesmanId or @SalesmanId=0)
else
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c 
	left join invSalesman s on c.SalesmanId=s.Id 
	where (c.CompanyId=@CompanyId or @CompanyId=0)
	and (c.SalesmanId=@SalesmanId or @SalesmanId=0)


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invCustomer t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from @Account t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null
  end
end 

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(200),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where AccountID1 is not null
union
select Id Debtor,0 CD,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.CashInHand


insert @CD 
select DiscountPaid,1,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0

insert @CD 
select Commission,0,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


if isnull(@WOC,0)=0
	insert @CD 
	select a.ID,0,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.BankAccount --where CompanyID=@CompanyID or @CompanyID=0



--Salesman
update c set c.Salesman=s.Name,c.SalesmanId=s.Id from @CD c join invSalesman s on c.Debtor=s.AccountId


declare @BR int
declare @CR int
declare @CC int
declare @BKR int
select @BR=isnull(BillwiseReceipt,0),@CR=isnull(ChequeReceipt,0),@CC=isnull(ChequeClearing,0),@BKR=isnull(BankReceipt,0) from aVoucherTypeSettings

--Cash
insert @Transaction
select t.CompanyId,Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and isnull(t.VoucherTypeID,0) not in(@BR,@CR,@BKR)
group by t.CompanyId,Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null



--Billwise Receipt
insert @Transaction
select t.CompanyID,Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CompanyId,Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name

delete t from @Transaction t
join aChequeClearingHdr cch on t.CompanyId=cch.CompanyID and t.PeriodID=cch.PeriodID and t.No=cch.No 
join aChequeClearingDtl ccd on cch.CompanyID=ccd.CompanyID and cch.PeriodID=ccd.PeriodID and cch.No=ccd.No
where t.VoucherTypeId=@CC and ccd.EVtypeID=@BR
---------------------------

--Cash Sales
insert @Transaction
select t.CompanyId,t.Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Notes,sum(NetTotal),null Discount,v.AccountVtypeId,t.PeriodID,t.SalesmanId,a1.Name
from invSalesHeader t
join invVoucherTypeDetails v on v.ID=t.VtypeId
join aAccount a on a.Id=t.CustomerId
join invOption o on o.CompanyID=@CompanyID
join aAccountSettings st on st.CompanyID=@CompanyID
join aAccount a1 on a1.Id=isnull(o.SalesCashAccountId,st.CashInHand)
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and t.PaymentMode=0
and (t.SalesmanId=@SalesmanId or @SalesmanId=0)
group by t.CompanyId,t.Date,v.Name,t.No,a.Name,s.Name,t.Notes,t.PeriodID,t.SalesmanId,cc.Name,v.AccountVtypeId,a1.Name



if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,CostCentre,VType,No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,CostCentre,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if object_id('spGetLedger') is not null drop proc spGetLedger

go

create proc spGetLedger
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int,
@OB bit,
@BS int=1,
@CostCentreID int=0,
@Type tinyint=null,
@Description nvarchar(50)=null,
@ModuleId int=1

as

set nocount on
set transaction isolation level read uncommitted

declare @Ledger table(LedgerAccountID int,LCode varchar(50),LedgerAccount nvarchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(100),VoucherTypeID int,VType nvarchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account nvarchar(100),CostCentre nvarchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Debit float,Credit float,AccountId int)

insert @Ledger(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@CostCentreID=@CostCentreID,@Type=@Type

--Secret
if @ModuleId=1
	delete l from @Ledger l join aAccount a on l.LedgerAccountId=a.Id where a.Secret=1

--Description
delete @Ledger where isnull(Description,'') not like '%'+@Description+'%'


--Company
if @CompanyID=0
	update l set l.Company=c.Name from @Ledger l join aCompany c on l.CompanyID=c.ID


--Balance
create table #LB(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount nvarchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(100),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account nvarchar(100),CostCentre nvarchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Debit float,Credit float,SR float,Discount float,AccountId int,Balance float)


if @Type=0
Begin
	insert #LB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,CostCentre,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,Balance)
	select row_number() over (order by Date,Debit desc,VoucherTypeId desc,No,SNo),*,null from @Ledger

	;with b as
	(select b.Ord,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from #LB b join #LB s on s.Ord<=b.Ord group by b.Ord)

	update s set s.Balance=b.Balance from #LB s join b on s.Ord=b.Ord

End
Else
Begin
	
	insert #LB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,CostCentre,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,Balance)
	select row_number() over (partition by LedgerAccount order by LedgerAccount,Date,Debit desc,VoucherTypeId desc,No,SNo),*,null from @Ledger

	create table #Bal(Ord int,LedgerAccount nvarchar(100),Balance float)
	insert #Bal
	select b.Ord,b.LedgerAccount,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from #LB b join #LB s on b.LedgerAccount=s.LedgerAccount and s.Ord<=b.Ord group by b.Ord,b.LedgerAccount

	update s set s.Balance=b.Balance from #LB s join #Bal b on s.LedgerAccount=b.LedgerAccount and s.Ord=b.Ord

End


if @Type=2
Begin
	declare @Sales int
	declare @DP int
	select @Sales=Sales,@DP=DiscountPaid from aAccountSettings where CompanyId=@CompanyId
	update #LB set SR=Credit,Credit=null where AccountId=@Sales and Credit is not null
	update #LB set Discount=Credit,Credit=null where AccountId=@DP and Credit is not null
End

if @BS<>1
	update #LB set Balance=@BS*Balance

-----------------------

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID) or @AccountID=0
Begin
	if @Type=0
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,LedgerAccount Name,Account,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
	Else
		select case when Ord=1 then LedgerAccount end LedgerAccount,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
End
else
Begin
	if @Type=2
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,Debit,Credit,SR,Discount,Balance from 
		(
		select 0 Ord,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(SR as money),@DecimalFormat)SR,convert(varchar,cast(Discount as money),@DecimalFormat)Discount,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select 1,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		union all
		select 2,null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,cast(sum(SR) as money),@DecimalFormat),convert(varchar,cast(sum(Discount) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0)-isnull(sum(SR),0)-isnull(sum(Discount),0) as money),@DecimalFormat) from #LB
		union all
		select 3,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		)a
		Order by Ord,Date,Debit desc,VoucherTypeId desc,No
	Else
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,Debit,Credit,Balance from
		(
		select 0 Ord,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select 1,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select 2,null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select 3,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		)a
		Order by Ord,Date,VoucherTypeId desc,No
End

go

if object_id('spGetLedger') is not null drop proc spGetLedger

go

create proc spGetLedger
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int,
@OB bit,
@BS int=1,
@CostCentreID int=0,
@Type tinyint=null,
@Description nvarchar(50)=null,
@ModuleId int=1

as

set nocount on
set transaction isolation level read uncommitted

declare @Ledger table(LedgerAccountID int,LCode varchar(50),LedgerAccount nvarchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(100),VoucherTypeID int,VType nvarchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account nvarchar(100),CostCentre nvarchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Debit float,Credit float,AccountId int)

insert @Ledger(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@CostCentreID=@CostCentreID,@Type=@Type

--Secret
if @ModuleId=1
	delete l from @Ledger l join aAccount a on l.LedgerAccountId=a.Id where a.Secret=1

--Description
delete @Ledger where isnull(Description,'') not like '%'+@Description+'%'


--Company
if @CompanyID=0
	update l set l.Company=c.Name from @Ledger l join aCompany c on l.CompanyID=c.ID


--Balance
create table #LB(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount nvarchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(100),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account nvarchar(100),CostCentre nvarchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Debit float,Credit float,SR float,Discount float,AccountId int,Balance float)


if @Type=0
Begin
	insert #LB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,CostCentre,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,Balance)
	select row_number() over (order by Date,Debit desc,VoucherTypeId desc,No,SNo),*,null from @Ledger

	;with b as
	(select b.Ord,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from #LB b join #LB s on s.Ord<=b.Ord group by b.Ord)

	update s set s.Balance=b.Balance from #LB s join b on s.Ord=b.Ord

End
Else
Begin
	
	insert #LB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,CostCentre,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,Balance)
	select row_number() over (partition by LedgerAccount order by LedgerAccount,Date,VoucherTypeId desc,No,SNo),*,null from @Ledger

	create table #Bal(Ord int,LedgerAccount nvarchar(100),Balance float)
	insert #Bal
	select b.Ord,b.LedgerAccount,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from #LB b join #LB s on b.LedgerAccount=s.LedgerAccount and s.Ord<=b.Ord group by b.Ord,b.LedgerAccount

	update s set s.Balance=b.Balance from #LB s join #Bal b on s.LedgerAccount=b.LedgerAccount and s.Ord=b.Ord

End


if @Type=2
Begin
	declare @Sales int
	declare @DP int
	select @Sales=Sales,@DP=DiscountPaid from aAccountSettings where CompanyId=@CompanyId
	update #LB set SR=Credit,Credit=null where AccountId=@Sales and Credit is not null
	update #LB set Discount=Credit,Credit=null where AccountId=@DP and Credit is not null
End

if @BS<>1
	update #LB set Balance=@BS*Balance

-----------------------

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID) or @AccountID=0
Begin
	if @Type=0
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,LedgerAccount Name,Account,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
	Else
		select case when Ord=1 then LedgerAccount end LedgerAccount,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
End
else
Begin
	if @Type=2
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,Debit,Credit,SR,Discount,Balance from 
		(
		select 0 Ord,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(SR as money),@DecimalFormat)SR,convert(varchar,cast(Discount as money),@DecimalFormat)Discount,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select 1,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		union all
		select 2,null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,cast(sum(SR) as money),@DecimalFormat),convert(varchar,cast(sum(Discount) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0)-isnull(sum(SR),0)-isnull(sum(Discount),0) as money),@DecimalFormat) from #LB
		union all
		select 3,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		)a
		Order by Ord,Date,VoucherTypeId desc,No
	Else
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,Debit,Credit,Balance from
		(
		select 0 Ord,PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select 1,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		union all
		select 2,null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0) as money),@DecimalFormat)from #LB
		union all
		select 3,null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
		)a
		Order by Ord,Date,VoucherTypeId desc,No
End

go

if not exists(select 1 from syscolumns where name='SalesmanID' and id=object_id('aCashReceiptHdr'))
	alter table aCashReceiptHdr add SalesmanID int foreign key references invSalesman(ID)

go

if OBJECT_ID('spSaveCashReceipt') is not null drop proc spSaveCashReceipt

go

create proc spSaveCashReceipt

@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@RepID int=null,
@Total float,
@xml xml,
@xmlBill xml=null,
@CompanyID int,
@PeriodID int,
@UserID int,
@SalesmanId int=null

as

set nocount on


--Duplicate RefNo
declare @Message varchar(100)
select @Message='This Ref.No already given for the Entry No. ' + cast(No as varchar) from aCashReceiptHdr where RefNo=@RefNo and No<>@No and CompanyID=@CompanyID and PeriodID=@PeriodID and Total is not null

if @Message is not null
Begin
	select @No No,@Message Message
	return
End


set xact_abort on
Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aCashReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aCashReceiptHdr([No],RefNo,Date,DebtorID,RepID,Total,CompanyID,PeriodID,UserID,SalesmanId)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@RepID,@Total,@CompanyID,@PeriodID,@UserID,@SalesmanId)
End
else
	update aCashReceiptHdr set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,RepID=@RepID,Total=@Total,UserID=@UserID,SalesmanId=@SalesmanId where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aCashReceiptDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @CashReceiptDtl table(SNo int,CreditorID int,CostCentreID int,Description nvarchar(100),Amount float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @CashReceiptDtl(SNo,CreditorID,CostCentreID,Description,Amount,Discount)
select SNo,CreditorID,nullif(CostCentreID,0),nullif(Description,''),Amount,nullif(Discount,0) from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
CreditorID int '@CreditorID',
CostCentreID int '@CostCentreID',
Description nvarchar(100) '@Description',
Amount float '@Amount',
Discount float '@Discount'
) 
where CreditorID>0
exec sp_xml_removedocument @idoc

insert aCashReceiptDtl(No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,CompanyID,PeriodID)
select @No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,@CompanyID,@PeriodID from @CashReceiptDtl

--aCashReceiptAllotedEntries

delete aCashReceiptAllotedEntries where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

exec sp_xml_preparedocument @idoc output,@xmlBill

insert aCashReceiptAllotedEntries(CompanyId,PeriodId,No,SNo,EPeriodId,EVoucherTypeId,ENo,ESNo,Paid)
select @CompanyId,@PeriodId,@No,Sno,nullif(PeriodId,0),VtypeId,ENo,ESNo,Paid from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
Sno int '@Sno',
PeriodId int '@PeriodId',
VtypeId int '@VtypeId',
ENo int '@No',
ESNo float '@ESNo',
Paid float '@Paid'
) 

exec sp_xml_removedocument @idoc




--Posting
declare @VoucherTypeID int
select @VoucherTypeID=CashReceipt from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

--Amount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,@DebtorID,CreditorID,Amount,isnull(Description,'Cash Received'),@RefNo,CostCentreID from @CashReceiptDtl where Amount<>0

--Discount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,10000+SNo,a.DiscountPaid,CreditorID,Discount,isnull(Description,'Discount'),@RefNo,CostCentreID from @CashReceiptDtl c,aAccountSettings a where c.Discount<>0 and a.CompanyID=@CompanyID

Commit
	
select @No No,@Message Message



go

if object_id('spGetCashReceipt') is not null drop proc spGetCashReceipt

go

create proc spGetCashReceipt
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.DebtorID,fh.RepID,isnull(a.Name,'CANCELLED') Debtor,fh.Total,fh.SalesmanID from aCashReceiptHdr fh
left join aAccount a on fh.DebtorID=a.ID
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
Begin

	select fd.No,0 SNo,fd.SNo KSNo,fd.CreditorID,a.Name Creditor,fd.CostCentreID,c.Name CostCentre,fd.Description,fd.Amount,fd.Discount,isnull(fd.Amount,0)+isnull(fd.Discount,0) NetAmount from aCashReceiptDtl fd 
	join aAccount a on fd.CreditorID=a.ID 
	left join aCostCentre c on fd.CostCentreID=c.ID
	where fd.CompanyID=@CompanyID and fd.PeriodID=@PeriodID and  fd.No=@No

	declare @ACRAE table(SNo int,PeriodId int,VtypeId int,VType varchar(50),No int,Date int,ESNo int,AccountId int,Account nvarchar(100),Amount float,Paid float,Balance float)

	insert @ACRAE(SNo,PeriodId,VtypeId,No,ESNo,Paid)
	select SNo,EPeriodId,EVoucherTypeId,ENo,ESNo,Paid from aCashReceiptAllotedEntries where CompanyID=@CompanyID and PeriodID=@PeriodID and  No=@No

	update a set a.vtype=v.name from @ACRAE a join aVoucherType v on a.VtypeId=v.ID

	update a set a.Date=t.Date,a.AccountId=case when Paid<0 then t.DebtorID else t.CreditorID end,a.Amount=t.Amount from @ACRAE a join aTransaction t on isnull(a.PeriodId,0)=isnull(t.PeriodID,0) and isnull(a.VtypeId,0)=isnull(t.VoucherTypeID,0) and isnull(a.No,0)=isnull(t.No,0) and isnull(a.ESNo,0)=isnull(t.SNo,0) where t.CompanyId=@CompanyId

	update a set a.Account=ac.name from @ACRAE a join aAccount ac on a.AccountId=ac.ID

	select cast(1 as bit)CHK,* from @ACRAE

End
go

if object_id('spGetVendors') is not null drop proc spGetVendors

go

create proc spGetVendors
@Date int,
@Inactive bit=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@UserID int=null
as

set nocount on
set xact_abort on

create table #Vendor (ID int,Code nvarchar(50),Name nvarchar(100),UnderAccountID int,Balance float,Leaf bit)

insert #Vendor(ID,Code,Name,UnderAccountID)
--select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryCreditors from aSubGroupSettings)
select distinct Vendors,a.Code,a.Name,a.UnderAccountID from aAccountSettings s join aAccount a on s.Vendors=a.ID where s.CompanyID=@CompanyID or @CompanyID=0

if object_id('invVendor') is not null
Begin
	if nullif(@UserID,0) is not null
		insert #Vendor(ID,Code,Name,UnderAccountID)
		select a.ID,a.Code,a.Name,a.UnderAccountID from aAccount a
		join invVendor c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID and uc.UserID=@UserID
		where a.AccountSubGroupID=(select SundryCreditors from aSubGroupSettings) and uc.Vendor=1
			
				
	Else
		insert #Vendor(ID,Code,Name,UnderAccountID)
		select a.ID,a.Code,a.Name,a.UnderAccountID from aAccount a
		join invVendor c on a.ID=c.AccountID
		where a.AccountSubGroupID=(select SundryCreditors from aSubGroupSettings) 
		and (c.CompanyID=@CompanyID or @CompanyID=0)
End


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_VendorProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invVendor t1
	join vw_VendorProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from #Vendor t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null
  end
end 

--Inactive
if @Inactive is not null
Begin
	if object_id('invVendor') is not null
	Begin
		delete c from #Vendor c join invVendor ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Inactive
	end
End


if object_id('invVendor') is not null
Begin
	--Company Customers
	insert #Vendor(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invVendor t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Vendor cu on t1.AccountId=cu.Id where cu.Id is null
End


--Balance
declare @Balance table
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert @Balance(Level,AccountID) 
select ID,ID from #Vendor where UnderAccountID is null or ID=UnderAccountID


while @@rowcount>0
	insert @Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from @Balance b join aAccount a on b.AccountID=a.UnderAccountID where a.ID not in(select AccountID from @Balance)

;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,-Amount Balance from aTransaction v join @Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0 or CompanyID is null
 union all
 select v.CreditorID,Amount from aTransaction v join @Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0 or CompanyID is null)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from @Balance b1 join b b2 on b1.AccountID=b2.AccountID
----------------------------------


--Accounts
update v set v.Balance=b.Balance from #Vendor v join @Balance b on v.ID=b.AccountID

select sum(Balance)Balance from #Vendor where id not in(select underaccountid from #Vendor where underaccountid is not null and Balance>0)

--Levels
;with b as (select * from @Balance where Balance is not null)
,lb as
(select b1.level,sum(b2.balance)Balance from @Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

update v set v.Balance=l.Balance from @Balance b join #Vendor v on b.accountid=v.id join lb l on b.Level=l.Level
--------------------

select ID,Code,Name,Balance Balance,UnderAccountID from #Vendor


go


if object_id('spTrialBalancePeriodwise') is not null drop proc spTrialBalancePeriodwise

go

create proc spTrialBalancePeriodwise
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@TypeID int=null,
@GroupID int=null,
@SubGroupID int=null,
@AccountID int=0,
@Level tinyint=0,
@CostCentreID int=0

as

set nocount on
set transaction isolation level read uncommitted

declare @Account table(ID int,Code nvarchar(50),Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,TypeID int,Level tinyint,SGCode varchar(50),SGName nvarchar(100))
insert @Account
select a.ID,a.Code,a.Name,a.NameinOL,a.UnderAccountID,g.AccountTypeID,0,s.Code,s.Name from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
where (g.AccountTypeID=@TypeID or @TypeID is null)
and (s.AccountGroupID=@GroupID or @GroupID is null)
and (a.AccountSubGroupID=@SubGroupID or @SubGroupID is null)
and (a.ID=@AccountID or @AccountID=0 and (a.UnderAccountID is null or a.ID=a.UnderAccountID))

--Drilling for Under Accounts
while @@rowcount>0
	insert @Account 
	select a1.ID,a1.Code,a1.Name,a1.NameinOL,a1.UnderAccountID,a2.TypeID,a2.Level+1,a2.SGCode,a2.SGName from aAccount a1 
	join @Account a2 on a1.UnderAccountID=a2.ID 
	left join @Account a3 on a1.ID=a3.ID
	where a3.ID is null

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption


declare @TB table(AccountID int,OB float,Debit float,Credit float,CB float)


insert @TB(AccountId,Debit,CB)
select t.DebtorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),sum(t.Amount) from aTransaction t
join @Account d on t.DebtorID=d.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.DebtorID


insert @TB(AccountId,Credit,CB)
select t.CreditorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),-sum(t.Amount) from aTransaction t
join @Account c on t.CreditorID=c.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CreditorID


--Climbing for Leveles
select @Level = case when @Level>max(Level) then 0 else max(Level)-@Level end from @Account
While @Level>0
Begin
	update t set t.AccountID=a.UnderAccountID from @TB t join @Account a on t.AccountID=a.iD where a.UnderAccountID is not null
	set @Level=@Level-1
End

if isnull(@CFIE,0)=0
Begin
	--Net Profit/Loss,Stock Movement from Previous Years
	if (@AccountID=0 and @SubGroupID is null)
	Begin
		declare @NP float
		declare @SM float
		declare @Stock float

		declare @PrevPeriodEndDate int
		select @PrevPeriodEndDate=[From]-1 from aPeriod where ID=@PeriodID

		exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@PrevPeriodEndDate,@NP=@NP output,@SM=@SM output,@Stock=@Stock output

		if @NP<>0
		Begin
			declare @Profit int
			select @Profit=Profit from aAccountSettings where (CompanyID=@CompanyID or @CompanyID=0)
			insert @TB(AccountID,OB) values (@Profit,-@NP)
		End

		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert @TB(AccountID,OB) values (@OS,@Stock)
				insert @TB(AccountID,OB) values (@OBE,-@Stock)
				insert @TB(AccountID,OB) values (@OBE,@SM)
			End
		End

	End
End
------------------

--OB
update @TB set OB=isnull(CB,0)-isnull(Debit,0)+isnull(Credit,0) where OB is null


--CB
update @TB set CB=isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0) where CB is null


--Final Data
select a.SGCode,a.SGName,a.Code,a.Name Account,a.NameInOL,sum(OB)OB,sum(Debit)Debit,sum(Credit)Credit,sum(CB)CB from @TB t
join @Account a on a.ID=t.AccountID
group by a.SGCode,a.SGName,a.Code,a.Name,a.NameInOL
having round(sum(OB),2)<>0 or round(sum(Debit),2)<>0 or round(sum(Credit),2)<>0 or round(sum(CB),2)<>0

go

if object_id('spLiabilities') is not null drop proc spLiabilities

go

create proc spLiabilities
@CompanyID int,
@CostCentreId int=0,
@Date int,
@Level tinyint=0,
@FromDate int

as

set nocount on
set transaction isolation level read uncommitted

declare @OptCompanyId int
select @OptCompanyId=@CompanyId
if @OptCompanyId=0 select @OptCompanyId=min(Id) from aCompany

declare @Account table(Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),ID int,Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,Level tinyint)

insert @Account
select t.Name,g.Name,s.Name,a.ID,a.Name,a.NameInOL,a.UnderAccountID,0 from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
join aAccountType t on g.AccountTypeID=t.ID
where (g.AccountTypeID=2 or g.AccountTypeID=3) and (a.UnderAccountID is null or a.ID=a.UnderAccountID)

--Drilling for Under Accounts
while @@rowcount>0
	insert @Account
	select a2.Type,a2.[Group],a2.SubGroup,a1.ID,a1.Name,a1.NameInOL,a1.UnderAccountID,a2.Level+1 from aAccount a1 
	join @Account a2 on a1.UnderAccountID=a2.ID 
	left join @Account a3 on a1.ID=a3.ID
	where a3.ID is null


declare @Liabilities table(Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),AccountID int,Account nvarchar(100),NameInOL nvarchar(100),Amount float)

declare @Profit int
select @Profit=Profit from aAccountSettings where CompanyID=@OptCompanyId

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,sum(tr.Amount) from aTransaction tr 
join @Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name+isnull(case when a.Id=@Profit and isnull(tr.Date,0)<@FromDate then +'(OB)' end,''),a.NameInOL,-sum(tr.Amount) from aTransaction tr 
join @Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,case when a.Id=@Profit and isnull(tr.Date,0)<@FromDate then +'(OB)' end

--Climbing for Levels
select @Level = case when @Level>max(Level) then 0 else max(Level)-@Level end from @Account
While @Level>0
Begin
	update t set t.AccountID=a.UnderAccountID,t.Account=u.Name,t.NameInOL=u.NameInOL from @Liabilities t join @Account a on t.AccountID=a.ID join @Account u on a.UnderAccountID=u.ID where a.UnderAccountID is not null
	set @Level=@Level-1
End



--Net Profit/Loss
declare @NP float
declare @OBDate int
select @OBDate=@FromDate-1

--OB
exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@OBDate,@NP=@NP output


insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount)
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(OB)',a.NameInOL,@NP from @Account a where a.Id=@Profit

exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=@FromDate,@Date=@Date,@NP=@NP output

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount)
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(Period)',a.NameInOL,@NP from @Account a where a.ID=@Profit



---------------------

--Closing Stock
if exists(select 1 from sysobjects where name='spStock')
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin 
		declare @Stock float
		exec spStock @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@ToDate=0,@Type=@Stock output
		
		insert @Liabilities(Type,[Group],SubGroup,Account,NameInOL,Amount)
		select top 1 a.Type,a.[Group],a.SubGroup,a.Name,a.NameInOL,@Stock from aAccountType t 
		join aAccountSettings st on st.CompanyId=@OptCompanyId
		join @Account a on st.OpeningBalanceEquity=a.ID
	End
End


if exists(select 1 from sysobjects where name='prPhyStockValue')  
Begin  
  set @Stock=NULL   
  exec prPhyStockValue @CompanyID=@CompanyID,@Date=20000101,@Stock=@Stock output
  insert @Liabilities(Type,[Group],SubGroup,Account,NameInOL,Amount)
  select top 1 a.Type,a.[Group],a.SubGroup,a.Name,a.NameInOL,@Stock from aAccountType t 
  join aAccountSettings st on st.CompanyId=@OptCompanyId
  join @Account a on st.OpeningBalanceEquity=a.ID
End  


select Type,[Group],SubGroup,Account,NameInOL,sum(Amount)Amount from @Liabilities 
group by Type,[Group],SubGroup,Account,NameInOL having round(sum(Amount),3)<>0

go

if object_id('spTrialBalancePeriodwise') is not null drop proc spTrialBalancePeriodwise

go

create proc spTrialBalancePeriodwise
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@TypeID int=null,
@GroupID int=null,
@SubGroupID int=null,
@AccountID int=0,
@Level tinyint=0,
@CostCentreID int=0

as

set nocount on
set transaction isolation level read uncommitted

declare @Account table(ID int,Code nvarchar(50),Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,TypeID int,Level tinyint,SGCode varchar(50),SGName nvarchar(100))
insert @Account
select a.ID,a.Code,a.Name,a.NameinOL,a.UnderAccountID,g.AccountTypeID,0,s.Code,s.Name from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
where (g.AccountTypeID=@TypeID or @TypeID is null)
and (s.AccountGroupID=@GroupID or @GroupID is null)
and (a.AccountSubGroupID=@SubGroupID or @SubGroupID is null)
and (a.ID=@AccountID or @AccountID=0 and (a.UnderAccountID is null or a.ID=a.UnderAccountID))

--Drilling for Under Accounts
while @@rowcount>0
	insert @Account 
	select a1.ID,a1.Code,a1.Name,a1.NameinOL,a1.UnderAccountID,a2.TypeID,a2.Level+1,a2.SGCode,a2.SGName from aAccount a1 
	join @Account a2 on a1.UnderAccountID=a2.ID 
	left join @Account a3 on a1.ID=a3.ID
	where a3.ID is null

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption


declare @TB table(AccountID int,OB float,Debit float,Credit float,CB float)


insert @TB(AccountId,Debit,CB)
select t.DebtorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),sum(t.Amount) from aTransaction t
join @Account d on t.DebtorID=d.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.DebtorID


insert @TB(AccountId,Credit,CB)
select t.CreditorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),-sum(t.Amount) from aTransaction t
join @Account c on t.CreditorID=c.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CreditorID


--Climbing for Leveles
select @Level = case when @Level>max(Level) then 0 else max(Level)-@Level end from @Account
While @Level>0
Begin
	update t set t.AccountID=a.UnderAccountID from @TB t join @Account a on t.AccountID=a.iD 
	where a.UnderAccountID is not null
	and a.ID not in(select ID from @TB)
	set @Level=@Level-1
End

if isnull(@CFIE,0)=0
Begin
	--Net Profit/Loss,Stock Movement from Previous Years
	if (@AccountID=0 and @SubGroupID is null)
	Begin
		declare @NP float
		declare @SM float
		declare @Stock float

		declare @PrevPeriodEndDate int
		select @PrevPeriodEndDate=[From]-1 from aPeriod where ID=@PeriodID

		exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@PrevPeriodEndDate,@NP=@NP output,@SM=@SM output,@Stock=@Stock output

		if @NP<>0
		Begin
			declare @Profit int
			select @Profit=Profit from aAccountSettings where (CompanyID=@CompanyID or @CompanyID=0)
			insert @TB(AccountID,OB) values (@Profit,-@NP)
		End

		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert @TB(AccountID,OB) values (@OS,@Stock)
				insert @TB(AccountID,OB) values (@OBE,-@Stock)
				insert @TB(AccountID,OB) values (@OBE,@SM)
			End
		End

	End
End
------------------

--OB
update @TB set OB=isnull(CB,0)-isnull(Debit,0)+isnull(Credit,0) where OB is null


--CB
update @TB set CB=isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0) where CB is null


--Final Data
select a.SGCode,a.SGName,a.Code,a.Name Account,a.NameInOL,sum(OB)OB,sum(Debit)Debit,sum(Credit)Credit,sum(CB)CB from @TB t
join @Account a on a.ID=t.AccountID
group by a.SGCode,a.SGName,a.Code,a.Name,a.NameInOL
having round(sum(OB),2)<>0 or round(sum(Debit),2)<>0 or round(sum(Credit),2)<>0 or round(sum(CB),2)<>0

go

if object_id('spTrialBalance') is not null drop proc spTrialBalance

go

create proc spTrialBalance
@CompanyID int,
@PeriodID int,
@Date int,
@TypeID int=null,
@GroupID int=null,
@SubGroupID int=null,
@AccountID int=0,
@Level tinyint=0,
@CostCentreID int=0

as

set nocount on
set transaction isolation level read uncommitted

create table #Account(ID int,Code nvarchar(50),Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,TypeID int,Level tinyint,SGCode varchar(50),SGName nvarchar(100))
insert #Account
select a.ID,a.Code,a.Name,a.NameinOL,a.UnderAccountID,g.AccountTypeID,0,s.Code,s.Name from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
where (g.AccountTypeID=@TypeID or @TypeID is null)
and (s.AccountGroupID=@GroupID or @GroupID is null)
and (a.AccountSubGroupID=@SubGroupID or @SubGroupID is null)
and (a.ID=@AccountId or @AccountId=0 and (a.UnderAccountID is null or a.ID=a.UnderAccountID))

--Drilling for Under Accounts
while @@rowcount>0
	insert #Account 
	select a1.ID,a1.Code,a1.Name,a1.NameinOL,a1.UnderAccountID,a2.TypeID,a2.Level+1,a2.SGCode,a2.SGName from aAccount a1 
	join #Account a2 on a1.UnderAccountID=a2.ID 
	left join #Account a3 on a1.ID=a3.ID
	where a3.ID is null

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption

create table #TB(AccountID int,Amount float)

insert #TB
select t.DebtorID,sum(t.Amount) from aTransaction t
join #Account d on t.DebtorID=d.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
--and (@CFIE=1 and t.PeriodID is null or t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@Date)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.DebtorID


insert #TB
select t.CreditorID,-sum(t.Amount) from aTransaction t
join #Account c on t.CreditorID=c.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
--and (@CFIE=1 and t.PeriodID is null or t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@Date)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CreditorID


--Climbing for Leveles
select @Level = case when @Level>max(Level) then 0 else max(Level)-@Level end from #Account
While @Level>0
Begin
	update t set t.AccountID=a.UnderAccountID from #TB t join #Account a on t.AccountID=a.iD 
	where a.UnderAccountID is not null
	and a.ID not in(select ID from #TB)
	set @Level=@Level-1
End

--select * from #Account where Id=122
--select * from #TB where AccountID=8 and Amount=-898533.76
--select * from #TB where AccountID=122 and Amount=-898533.76

if isnull(@CFIE,0)=0
Begin
	--Net Profit/Loss,Stock Movement from Previous Years
	if (@AccountId=0 and @SubGroupID is null)
	Begin
		declare @NP float
		declare @SM float
		declare @Stock float

		declare @PrevPeriodEndDate int
		select @PrevPeriodEndDate=convert(varchar,cast(cast([From] as varchar) as smalldatetime)-1,112) from aPeriod where ID=@PeriodID
		select @PrevPeriodEndDate=@Date where @Date<@PrevPeriodEndDate
		exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@PrevPeriodEndDate,@NP=@NP output,@SM=@SM output,@Stock=@Stock output
		
		if @NP<>0
		Begin
			declare @Profit int
			select @Profit=Profit from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			insert #TB(AccountID,Amount) values (@Profit,-@NP)
		End

		--if @SM<>0
		--Begin
		--	declare @SIH int
		--	select @SIH=StockInHand from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
		--	insert #TB(AccountID,Amount) values (@SIH,@SM)
		--End

		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert #TB(AccountID,Amount) values (@OS,@Stock)
				insert #TB(AccountID,Amount) values (@OBE,-@Stock)
				insert #TB(AccountID,Amount) values (@OBE,@SM)
			End
		End
	End
End
------------------

--select Amount from #TB where AccountID=122 return

--Final Data
select a.SGCode,a.SGName,a.Code,a.Name Account,a.NameInOL,case when Amount>0 then Amount end Debit,case when Amount<0 then abs(Amount) end Credit from
(select AccountID,sum(Amount)Amount from #TB group by AccountID having round(isnull(sum(Amount),0),2)<>0)t
join #Account a on a.ID=t.AccountID

go

if object_id('spTrialBalance') is not null drop proc spTrialBalance

go

create proc spTrialBalance
@CompanyID int,
@PeriodID int,
@Date int,
@TypeID int=null,
@GroupID int=null,
@SubGroupID int=null,
@AccountID int=0,
@Level tinyint=0,
@CostCentreID int=0

as

set nocount on
set transaction isolation level read uncommitted

create table #Account(ID int,Code nvarchar(50),Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,TypeID int,Level tinyint,SGCode varchar(50),SGName nvarchar(100))
insert #Account
select a.ID,a.Code,a.Name,a.NameinOL,a.UnderAccountID,g.AccountTypeID,0,s.Code,s.Name from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
where (g.AccountTypeID=@TypeID or @TypeID is null)
and (s.AccountGroupID=@GroupID or @GroupID is null)
and (a.AccountSubGroupID=@SubGroupID or @SubGroupID is null)
and (a.ID=@AccountId or @AccountId=0 and (a.UnderAccountID is null or a.ID=a.UnderAccountID))

--Drilling for Under Accounts
while @@rowcount>0
	insert #Account 
	select a1.ID,a1.Code,a1.Name,a1.NameinOL,a1.UnderAccountID,a2.TypeID,a2.Level+1,a2.SGCode,a2.SGName from aAccount a1 
	join #Account a2 on a1.UnderAccountID=a2.ID 
	left join #Account a3 on a1.ID=a3.ID
	where a3.ID is null

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption

create table #TB(AccountID int,Amount float)


insert #TB
select t.DebtorID,sum(t.Amount) from aTransaction t
join #Account d on t.DebtorID=d.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
--and (@CFIE=1 and t.PeriodID is null or t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@Date)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.DebtorID


insert #TB
select t.CreditorID,-sum(t.Amount) from aTransaction t
join #Account c on t.CreditorID=c.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
--and (@CFIE=1 and t.PeriodID is null or t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@Date)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CreditorID


--Climbing for Leveles
While exists(select 1 from #TB t join #Account a on t.AccountID=a.Id where a.Level>@Level)
Begin
	update t set t.AccountID=a.UnderAccountID from #TB t 
	join #Account a on t.AccountID=a.iD 
	where a.UnderAccountID is not null
	and a.Level>@Level
End

if isnull(@CFIE,0)=0
Begin
	--Net Profit/Loss,Stock Movement from Previous Years
	if (@AccountId=0 and @SubGroupID is null)
	Begin
		declare @NP float
		declare @SM float
		declare @Stock float

		declare @PrevPeriodEndDate int
		select @PrevPeriodEndDate=convert(varchar,cast(cast([From] as varchar) as smalldatetime)-1,112) from aPeriod where ID=@PeriodID
		select @PrevPeriodEndDate=@Date where @Date<@PrevPeriodEndDate
		exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@PrevPeriodEndDate,@NP=@NP output,@SM=@SM output,@Stock=@Stock output
		
		if @NP<>0
		Begin
			declare @Profit int
			select @Profit=Profit from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			insert #TB(AccountID,Amount) values (@Profit,-@NP)
		End

		--if @SM<>0
		--Begin
		--	declare @SIH int
		--	select @SIH=StockInHand from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
		--	insert #TB(AccountID,Amount) values (@SIH,@SM)
		--End

		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert #TB(AccountID,Amount) values (@OS,@Stock)
				insert #TB(AccountID,Amount) values (@OBE,-@Stock)
				insert #TB(AccountID,Amount) values (@OBE,@SM)
			End
		End
	End
End
------------------


--Final Data
select a.SGCode,a.SGName,a.Code,a.Name Account,a.NameInOL,case when Amount>0 then Amount end Debit,case when Amount<0 then abs(Amount) end Credit from
(select AccountID,sum(Amount)Amount from #TB group by AccountID having round(isnull(sum(Amount),0),2)<>0)t
join #Account a on a.ID=t.AccountID

go

if object_id('spTrialBalancePeriodwise') is not null drop proc spTrialBalancePeriodwise

go

create proc spTrialBalancePeriodwise
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@TypeID int=null,
@GroupID int=null,
@SubGroupID int=null,
@AccountID int=0,
@Level tinyint=0,
@CostCentreID int=0

as

set nocount on
set transaction isolation level read uncommitted

declare @Account table(ID int,Code nvarchar(50),Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,TypeID int,Level tinyint,SGCode varchar(50),SGName nvarchar(100))
insert @Account
select a.ID,a.Code,a.Name,a.NameinOL,a.UnderAccountID,g.AccountTypeID,0,s.Code,s.Name from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
where (g.AccountTypeID=@TypeID or @TypeID is null)
and (s.AccountGroupID=@GroupID or @GroupID is null)
and (a.AccountSubGroupID=@SubGroupID or @SubGroupID is null)
and (a.ID=@AccountID or @AccountID=0 and (a.UnderAccountID is null or a.ID=a.UnderAccountID))

--Drilling for Under Accounts
while @@rowcount>0
	insert @Account 
	select a1.ID,a1.Code,a1.Name,a1.NameinOL,a1.UnderAccountID,a2.TypeID,a2.Level+1,a2.SGCode,a2.SGName from aAccount a1 
	join @Account a2 on a1.UnderAccountID=a2.ID 
	left join @Account a3 on a1.ID=a3.ID
	where a3.ID is null

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption


declare @TB table(AccountID int,OB float,Debit float,Credit float,CB float)


insert @TB(AccountId,Debit,CB)
select t.DebtorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),sum(t.Amount) from aTransaction t
join @Account d on t.DebtorID=d.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or d.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.DebtorID


insert @TB(AccountId,Credit,CB)
select t.CreditorID,sum(case when t.Date between @FromDate and @ToDate then t.Amount end),-sum(t.Amount) from aTransaction t
join @Account c on t.CreditorID=c.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID) 
and (t.PeriodID is null or t.PeriodID=@PeriodID or c.TypeID in(1,2,3) or @CFIE=1) 
and (t.Date is null or t.Date<=@ToDate)
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CreditorID


--Climbing for Leveles
--select @Level = case when @Level>max(Level) then 0 else max(Level)-@Level end from @Account
--While @Level>0
--Begin
--	update t set t.AccountID=a.UnderAccountID from @TB t join @Account a on t.AccountID=a.iD where a.UnderAccountID is not null
--	set @Level=@Level-1
--End

While exists(select 1 from @TB t join @Account a on t.AccountID=a.Id where a.Level>@Level)
Begin
	update t set t.AccountID=a.UnderAccountID from @TB t 
	join @Account a on t.AccountID=a.iD 
	where a.UnderAccountID is not null
	and a.Level>@Level
End

if isnull(@CFIE,0)=0
Begin
	--Net Profit/Loss,Stock Movement from Previous Years
	if (@AccountID=0 and @SubGroupID is null)
	Begin
		declare @NP float
		declare @SM float
		declare @Stock float

		declare @PrevPeriodEndDate int
		select @PrevPeriodEndDate=[From]-1 from aPeriod where ID=@PeriodID

		exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=20000101,@Date=@PrevPeriodEndDate,@NP=@NP output,@SM=@SM output,@Stock=@Stock output

		if @NP<>0
		Begin
			declare @Profit int
			select @Profit=Profit from aAccountSettings where (CompanyID=@CompanyID or @CompanyID=0)
			insert @TB(AccountID,OB) values (@Profit,-@NP)
		End

		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert @TB(AccountID,OB) values (@OS,@Stock)
				insert @TB(AccountID,OB) values (@OBE,-@Stock)
				insert @TB(AccountID,OB) values (@OBE,@SM)
			End
		End

	End
End
------------------

--OB
update @TB set OB=isnull(CB,0)-isnull(Debit,0)+isnull(Credit,0) where OB is null


--CB
update @TB set CB=isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0) where CB is null


--Final Data
select a.SGCode,a.SGName,a.Code,a.Name Account,a.NameInOL,sum(OB)OB,sum(Debit)Debit,sum(Credit)Credit,sum(CB)CB from @TB t
join @Account a on a.ID=t.AccountID
group by a.SGCode,a.SGName,a.Code,a.Name,a.NameInOL
having round(sum(OB),2)<>0 or round(sum(Debit),2)<>0 or round(sum(Credit),2)<>0 or round(sum(CB),2)<>0

go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete,update,insert
AS
BEGIN
	
	--IF ADDING NEW LINE, NEED TO ADD IN MULTIJOURNAL DISPLAY SP

	SET NOCOUNT ON

	-- Add your code for checking the values from deleted
	Declare @Message varchar(max)	
	if object_id('aBillwiseReceiptDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE RECEIPT : '+ cast(b.No as varchar) from deleted t 
		join aBillwiseReceiptDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.CustomerId or t.DebtorId=h.CustomerId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aChequeClearingDtl') is not null
	Begin
		select @Message='THIS ENTRY HAS REFERENCE IN CHEQUE CLEARING : '+ cast(b.No as varchar) from deleted t 
		join aChequeClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aBillwisePaymentDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE PAYMENT : '+ cast(b.No as varchar) from deleted t 
		join aBillwisePaymentDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.VendorId or t.DebtorId=h.VendorId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End  
	End

	select @Message='THIS ENTRY HAS REFERENCE IN CREDIT CARD CLEARING : '+ cast(b.No as varchar) from deleted t join aCreditCardClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End  
	
	select @Message='DATE IS OUT OF SCOPE OF THE PERIOD : '+ p.Name  from inserted t 
	--join aPeriod p on t.PeriodId=p.Id and t.Date not between p.[From] and p.[To]
	join aPeriod p on t.PeriodId=p.Id and t.Date>p.[To]
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End

END

GO

if OBJECT_ID('spSaveCompany') is not null drop proc spSaveCompany

go

create proc spSaveCompany
@ID int,
@Code nvarchar(25),
@Name nvarchar(50),
@Address nvarchar(300),
@Phone nvarchar(50),
@EMail nvarchar(50),
@AccountID int,
@RegNo nvarchar(50)=null,
@PrintName nvarchar(100)=null
as 

set nocount on

if exists(select 1 from aCompany where ID<>@ID and Code=@Code)
	Begin
	select 1 status ,'Duplicate Code' Message
	return		
	End

if exists(select 1 from aCompany where ID<>@ID and Name=@Name)
	Begin
	select 2 status ,'Duplicate Name' Message
	return		
	End

if exists(select 1 from aCompany where ID<>@ID and AccountID=@AccountID)
	Begin
	select 3 status ,'Duplicate Account' Message
	return		
	End


if @ID=0
Begin
	select @ID=isnull(max(ID),0)+1 from aCompany
	insert aCompany(ID,Code,Name,Address,Phone,EMail,AccountID,RegNo,PrintName)
	values(@ID,@Code,@Name,nullif(@Address,''),nullif(@Phone,''),nullif(@EMail,''),nullif(@AccountID,0),@RegNo,@PrintName)
End
else
	update aCompany set Code=@Code,Name=@Name,Address=nullif(@Address,''),Phone=nullif(@Phone,''),EMail=nullif(@EMail,''),AccountID=nullif(@AccountID,0),RegNo=@RegNo,PrintName=@PrintName where ID=@ID


if object_id('invOption') is not null
Begin
	if not exists(select 1 from invOption where CompanyID=@ID)
		insert invOption(ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,CompanyID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,CompanyTransferCompanyFromId,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces,SalesSerialNoMandatory)
		select top 1 ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,@ID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,@Id,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces,SalesSerialNoMandatory from invOption
	if not exists(select 1 from invOption where CompanyID=@ID)
		insert invOption(CompanyID,ItemCodeLength,QtyDecimalPlaces,DockContent)
		select @ID,5,2,1
End

if object_id('invReportFilter') is not null
Begin
	if not exists(select 1 from invReportFilter where CompanyID=@ID)
	Begin
		declare @ReportID int
		select @ReportID=max(ID) from invReportFilter

		insert invReportFilter(ID,Name,Type,Properties,GroupBy,OrderBy,GroupTotal,ColumnOrder,Summary,SetAsDefault,GroupRow,UserId,CompanyID)
		select @ReportID+ID,Name,Type,Properties,GroupBy,OrderBy,GroupTotal,ColumnOrder,Summary,SetAsDefault,GroupRow,UserId,@ID from invReportFilter
		where CompanyID=(select min(ID) from aCompany)
	End
End


if not exists(select 1 from aAccountSettings where CompanyID=@ID)
	insert aAccountSettings(CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,CompanyID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity,OpeningStock)
	select top 1 CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,@ID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity,OpeningStock from aAccountSettings


if not exists(select 1 from invProjectSettings where CompanyID=@ID)
	insert invProjectSettings(PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,CompanyId)
	select top 1 PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,@ID from invProjectSettings


select 0 status ,'Saved Successfully' Message

go

if object_id('spGetJournalDtl') is not null drop proc spGetJournalDtl

go

create proc spGetJournalDtl
@CompanyID int,
@PeriodID int,
@No int
as
select f.SNo,a.Name,f.Description,f.Amount,f.Tax,c.Name CostCentre from aJournalDtl f join aAccount a on f.AccountID=a.ID 
left outer join aCostCentre c on f.CostCentreID =c.ID 
where f.CompanyID=@CompanyID and f.PeriodID=@PeriodID and f.No=@No

go

if object_id('spGetReceiptReport') is not null drop proc spGetReceiptReport

go

create proc spGetReceiptReport
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@CreditorId int,
@SalesmanId int=0
as

declare @Data table(PeriodID int,CompanyID int,No int,RefNo varchar(50),Date smalldatetime,Debtor nvarchar(100),Sno int,Creditor nvarchar(100),
Description nvarchar(300),Amount varchar(25),Discount varchar(25),Total varchar(25))

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

insert @Data(PeriodID,CompanyID,No,RefNo,Date,Debtor,Sno,Creditor,Description,Amount,Discount,Total)
select t2.PeriodID,t2.CompanyID,t1.No,RefNo,cast(cast(Date as varchar) as smalldatetime)Date,ac.Name ,Sno,a.Name ,
Description,Amount,isnull(Discount,0)Discount
,Amount+isnull(Discount,0) Total 
from aCashReceiptDtl t1 join aCashReceiptHdr t2 on t1.No=t2.No and t1.CompanyID=t2.CompanyID and t1.PeriodID=t2.PeriodID
join aAccount a on  t1.CreditorID=a.ID
join aAccount ac on t2.DebtorID=ac.ID
left outer join aCostCentre C on t1.CostCentreID=a.ID
where t2.Date between @FromDate and @ToDate and t2.CompanyID=@CompanyID and t2.PeriodID=@PeriodID
and (@CreditorId=0 or t1.CreditorID=@CreditorId)
and (@SalesmanId=0 or t2.SalesmanId=@SalesmanId)
order by No,t1.Sno

select * from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
union all
select null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(CAST( Amount as float)) as money),4),convert(varchar,cast(sum(CAST( Discount as float)) as money),4),convert(varchar,cast(sum(CAST( Total as float)) as money),4) from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete,update,insert
AS
BEGIN
	
	--IF ADDING NEW LINE, NEED TO ADD IN MULTIJOURNAL DISPLAY SP

	SET NOCOUNT ON

	-- Add your code for checking the values from deleted
	Declare @Message varchar(max)	
	if object_id('aBillwiseReceiptDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE RECEIPT : '+ cast(b.No as varchar) from deleted t 
		join aBillwiseReceiptDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.CustomerId or t.DebtorId=h.CustomerId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aChequeClearingDtl') is not null
	Begin
		select @Message='THIS ENTRY HAS REFERENCE IN CHEQUE CLEARING : '+ cast(b.No as varchar) from deleted t 
		join aChequeClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aBillwisePaymentDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE PAYMENT : '+ cast(b.No as varchar) from deleted t 
		join aBillwisePaymentDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.VendorId or t.DebtorId=h.VendorId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End  
	End

	select @Message='THIS ENTRY HAS REFERENCE IN CREDIT CARD CLEARING : '+ cast(b.No as varchar) from deleted t join aCreditCardClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End  
	
	select @Message='DATE IS OUT OF SCOPE OF THE PERIOD : '+ p.Name  from inserted t 
	join aPeriod p on t.PeriodId=p.Id and t.Date not between p.[From] and p.[To]
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End

END

GO

if object_id('spVendorBillwiseStatement') is not null drop proc spVendorBillwiseStatement

go

create proc spVendorBillwiseStatement
@CompanyID int,
@VendorID int,
@Date int

as

set transaction isolation level read uncommitted

declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @aTransaction table(PeriodId int,VoucherTypeID int,No int,SNo int,Date int,Age int,PNo int,Debit float,Credit float,Description nvarchar(100))


insert @aTransaction(PeriodId,VoucherTypeID,No,SNo,Date,Credit)
select PeriodId,VoucherTypeID,No,t.SNo,t.Date,case when DebtorId=@VendorID then -1 else 1 end*Amount 
from aTransaction t
where (t.DebtorID=@VendorID or t.CreditorID=@VendorID)
and CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,0)<=@Date


--Advance
insert @aTransaction(PeriodId,VoucherTypeID,No,Date,Credit)
select PeriodId,@VoucherTypeID,No,Date,-Advance from aBillwisePaymentHdr
where VendorID=@VendorID
and CompanyID=@CompanyID 
and Advance>0
and isnull(Date,0)<=@Date

declare @Entries table(PeriodId int,VoucherTypeID int,No int,SNo int,Date int)
insert @Entries(PeriodId,VoucherTypeID,No,SNo,Date)
select distinct PeriodId,VoucherTypeID,No,SNo,Date from @aTransaction


insert @aTransaction(PeriodId,VoucherTypeID,No,SNo,Date,PNo,Debit)
select e.PeriodId,e.VoucherTypeID,e.No,e.SNo,h.Date,b.No,b.Paid+isnull(b.Discount,0) from @Entries e
join aBillwisePaymentDtl b on isnull(e.PeriodId,0)=isnull(b.EPeriodId,0) and isnull(e.VoucherTypeId,0)=isnull(b.EVoucherTypeID,0) and isnull(e.No,0)=isnull(b.ENo,0) and isnull(e.SNo,0)=isnull(b.ESNo,0)
join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No
where b.CompanyId=@CompanyId

declare @ZeroBills table(PeriodId int,VoucherTypeID int,No int)
insert @ZeroBills select PeriodId,VoucherTypeID,No from @aTransaction group by PeriodId,VoucherTypeID,No having round(sum(isnull(Credit,0)-isnull(Debit,0)),2)=0


delete a from @aTransaction a join @ZeroBills b on isnull(a.PeriodId,0)=isnull(b.PeriodId,0) and isnull(a.VoucherTypeID,0)=isnull(b.VoucherTypeID,0) and isnull(a.No,0)=isnull(b.No,0)

--Description
declare @Desc table(Sno int,Date int,PNo int,Vtype varchar(50),ENo int,Amount float)
insert @Desc
select row_number()over(order by (select 1))Sno,t.Date,t.PNo,v.Name,b.ENo,b.Paid from @aTransaction t 
join aBillwisePaymentDtl b on t.PNo=b.No
join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and t.Date=h.Date and h.VendorId=@VendorId
join aVoucherType v on b.EVoucherTypeId=v.Id
where t.debit>0 and b.Paid<0
declare @i int
set @i=1
while @i<4
begin
	update t set t.Description=isnull(t.Description+', ','')+d.Vtype+' - '+cast(d.ENo as varchar)+' - '+cast(-d.Amount as varchar) from @aTransaction t join @Desc d on t.Date=d.Date and t.PNo=d.PNo and t.Debit>0 and d.SNo=@i
	set @i=@i+1
end
-------------

update @aTransaction set Age=datediff(D,cast(cast(Date as varchar) as smalldatetime),current_timestamp) where PNo is null

select v.Name Type,t.No,t.PNo,cast(cast(Date as varchar) as smalldatetime)Date,Age,sum(Debit)Debit,sum(Credit)Credit,t.Description from @aTransaction t
join aVoucherType v on t.VoucherTypeId=v.Id
group by v.Name,t.No,t.PNo,cast(cast(Date as varchar) as smalldatetime),Age,t.Description,PeriodId,VoucherTypeID
order by PeriodId,VoucherTypeID,No,Credit desc


go


if exists(select * from sysIndexes where name='IndaMultiJournalDtl') drop Index aMultiJournalDtl.IndaMultiJournalDtl
go
Create unique clustered Index IndaMultiJournalDtl on aMultiJournalDtl(CompanyId,PeriodId,No,DebtorId,CreditorId,SNo,CostCentreId) with fillfactor=90

go

if OBJECT_ID('spSaveJournal') is not null drop proc spSaveJournal

go

create proc spSaveJournal

@No int,
@RefNo nvarchar(50),
@Date int,
@DrCr bit,
@AccountID int,
@Total float,
@xml xml,
@CompanyID int,
@PeriodID int
as

set nocount on
set xact_abort on

Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aJournalHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aJournalHdr([No],RefNo,Date,DrCr,AccountID,Total,CompanyID,PeriodID)
	values(@No,nullif(@RefNo,''),@Date,@DrCr,@AccountID,@Total,@CompanyID,@PeriodID)
End
else
	update aJournalHdr set RefNo=nullif(@RefNo,''),Date=@Date,DrCr=@DrCr,AccountID=@AccountID,Total=@Total where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aJournalDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @JournalDtl table(SNo int,AccountID int,CostCentreID int,Description nvarchar(100),Amount float,Tax float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @JournalDtl(SNo,AccountID,CostCentreID,Description,Amount,Tax)
select row_number()over(order by SNo),AccountID,nullif(CostCentreID,0),nullif(Description,''),Amount,Tax from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
AccountID int '@AccountID',
CostCentreID int '@CostCentreID',
Description nvarchar(100) '@Description',
Amount float '@Amount',
Tax float '@Tax'
) 
where AccountID>0
exec sp_xml_removedocument @idoc

insert aJournalDtl(No,SNo,AccountID,CostCentreID,Description,Amount,Tax,CompanyID,PeriodID)
select @No,SNo,AccountID,CostCentreID,Description,Amount,Tax,@CompanyID,@PeriodID from @JournalDtl

--Posting
declare @VoucherTypeID int
select @VoucherTypeID=Journal from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

if @DrCr=1
Begin
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
	select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,AccountID,@AccountID,Amount+isnull(Tax,0),Description,@RefNo,CostCentreID from @JournalDtl

	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
	select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,j.SNo,a.InputTax,j.AccountID,j.Tax,j.Description,@RefNo,j.CostCentreID from @JournalDtl j
	join aAccountSettings a on a.CompanyID=@CompanyID
	where j.Tax<>0


End
Else
Begin
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
	select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,@AccountID,AccountID,Amount+isnull(Tax,0),Description,@RefNo,CostCentreID from @JournalDtl

	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
	select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,j.SNo,isnull(a.InputTax,0),@AccountID,j.Tax,j.Description,@RefNo,j.CostCentreID from @JournalDtl j
	join aAccountSettings a on a.CompanyID=@CompanyID
	where j.Tax<>0
End


Commit
	
select @No 



go

if OBJECT_ID('spSaveMultiJournal') is not null drop proc spSaveMultiJournal

go

create proc spSaveMultiJournal

@No int,
@RefNo nvarchar(50),
@Date int,
@xml xml,
@CompanyID int,
@PeriodID int
as

set nocount on
set xact_abort on

Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aMultiJournalHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aMultiJournalHdr([No],RefNo,Date,CompanyID,PeriodID)
	values(@No,nullif(@RefNo,''),@Date,@CompanyID,@PeriodID)
End
else
	update aMultiJournalHdr set RefNo=nullif(@RefNo,''),Date=@Date where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aMultiJournalDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @MultiJournalDtl table(SNo int,DebtorID int,CreditorID int,CostCentreID int,Description nvarchar(100),AdditionalDescription nvarchar(100),Amount float,Tax float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @MultiJournalDtl(SNo,DebtorID,CreditorID,CostCentreID,Description,AdditionalDescription,Amount,Tax)
select row_number()over(order by SNo),DebtorID,CreditorID,nullif(CostCentreID,0),nullif(Description,''),nullif(AdditionalDescription,''),Amount,Tax from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
DebtorID int '@DebtorID',
CreditorID int '@CreditorID',
CostCentreID int '@CostCentreID',
Description nvarchar(100) '@Description',
AdditionalDescription nvarchar(100) '@AdditionalDescription',
Amount float '@Amount',
Tax float '@Tax'
) 
where DebtorID>0 and CreditorID>0

exec sp_xml_removedocument @idoc

insert aMultiJournalDtl(No,SNo,DebtorID,CreditorID,CostCentreID,Description,AdditionalDescription,Amount,Tax,CompanyID,PeriodID)
select @No,SNo,DebtorID,CreditorID,CostCentreID,Description,AdditionalDescription,Amount,Tax,@CompanyID,@PeriodID from @MultiJournalDtl

--Posting
declare @VoucherTypeID int
select @VoucherTypeID=MultiJournal from aVoucherTypeSettings

ALTER TABLE aTransaction Disable TRIGGER triggeraTransaction
delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID
ALTER TABLE aTransaction Enable TRIGGER triggeraTransaction

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,AdditionalDescription,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,DebtorID,CreditorID,Amount,Description,AdditionalDescription,@RefNo,CostCentreID from @MultiJournalDtl


insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,AdditionalDescription,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,j.SNo,a.InputTax,j.CreditorID,j.Tax,j.Description,AdditionalDescription,@RefNo,j.CostCentreID from @MultiJournalDtl j
join aAccountSettings a on a.CompanyID=@CompanyID
where j.Tax>0



insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,AdditionalDescription,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,j.SNo,a.OutputTax,j.CreditorID,j.Tax,j.Description,AdditionalDescription,@RefNo,j.CostCentreID from @MultiJournalDtl j
join aAccountSettings a on a.CompanyID=@CompanyID
where j.Tax<0

Commit
	
select @No 



go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete,update,insert
AS
BEGIN
	
	--IF ADDING NEW LINE, NEED TO ADD IN MULTIJOURNAL DISPLAY SP

	SET NOCOUNT ON

	-- Add your code for checking the values from deleted
	Declare @Message varchar(max)	
	if object_id('aBillwiseReceiptDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE RECEIPT : '+ cast(b.No as varchar) from deleted t 
		join aBillwiseReceiptDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.CustomerId or t.DebtorId=h.CustomerId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aChequeClearingDtl') is not null
	Begin
		select @Message='THIS ENTRY HAS REFERENCE IN CHEQUE CLEARING : '+ cast(b.No as varchar) from deleted t 
		join aChequeClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aBillwisePaymentDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE PAYMENT : '+ cast(b.No as varchar) from deleted t 
		join aBillwisePaymentDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.VendorId or t.DebtorId=h.VendorId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End  
	End

	select @Message='THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar)+' HAS REFERENCE IN CREDIT CARD CLEARING : '+ cast(b.No as varchar) from deleted t 
	join aCreditCardClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
	left join aVoucherType v on t.VoucherTypeId=v.Id
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End  
	
	select @Message='DATE IS OUT OF SCOPE OF THE PERIOD : '+ p.Name  from inserted t 
	join aPeriod p on t.PeriodId=p.Id and t.Date not between p.[From] and p.[To]
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End

END

GO

if object_id('spGetSalesmanSummary') is not null drop proc spGetSalesmanSummary

go

create proc spGetSalesmanSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null

as

create table #Customer (ID int,Name nvarchar(100),SalesmanId int)
insert #Customer select AccountID,Name,SalesmanId  from invCustomer where @SalesmanID=0 or SalesmanID=@SalesmanID


--Property Filtering
if LEN(@PropertyFilter) > 0
begin
	if OBJECT_ID('vw_CustomerProperty') is not null
	begin
	declare @T1 table (Id int)
	insert @T1 exec
	('
	select t1.AccountID from invCustomer t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
	')
	delete t1 from #Customer t1 
	left outer join @T1 t2 on t1.ID = t2.Id 
	where t2.Id is null
	end
end

create table #aTransaction(Salesman nvarchar(100),OB float,Qty float,Debit float,Credit float)

--Trnasactions
insert #aTransaction(Salesman,OB,Debit,Credit)
select s.Name,case when Date is null or Date<@FromDate then 1 end,sum(case when t.DebtorID=c.ID then Amount end),sum(case when t.CreditorID=c.ID then Amount end) from aTransaction t
join #Customer c on t.DebtorID=c.ID or t.CreditorID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (t.CompanyID=@CompanyID or @CompanyID=0)
and (t.Date<=@ToDate or t.Date is null)
group by s.Name,case when Date is null or Date<@FromDate then 1 end


--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where OB=1


--Qty
insert #aTransaction(Salesman,Qty)
select s.Name,sum(sd.Qty) from invSalesHeader sh
join invSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sh.CustomerID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by s.Name

insert #aTransaction(Salesman,Qty)
select s.Name,sum(sd.Qty) from invMultiSalesHeader sh
join invMultiSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sd.CustomerID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by s.Name


declare @Line varchar(25)
set @Line=replicate('-',25) 

create table #Balance(Salesman nvarchar(100),OB money,Qty float,Debit money,Credit money,CB money,Diff money) 
insert #Balance
select Salesman,sum(OB),sum(Qty),sum(Debit),sum(Credit)
,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),
sum(isnull(Debit,0)-isnull(Credit,0))
from #aTransaction
group by Salesman

if (@Status=2)
 delete #Balance where CB<=0

--Final
select Salesman,
convert(varchar,OB,4)OB,convert(varchar,Qty,4)Qty,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB,convert(varchar,Diff,4)Diff 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Qty),4)Qty,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(CB,0)),4)CB,convert(varchar,sum(isnull(Diff,0)),4)Diff from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line

go

if object_id('aCustomerCentreReportTypes') is null create table aCustomerCentreReportTypes(ID int,Name varchar(100),Checked bit unique(ID))

go

if not exists(select 1 from aCustomerCentreReportTypes where id=1)
	insert aCustomerCentreReportTypes values(1,'Ledger',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=2)
	insert aCustomerCentreReportTypes values(2,'Sales/Collection',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=5)
	insert aCustomerCentreReportTypes values(5,'Rental/Collection',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=3)
	insert aCustomerCentreReportTypes values(3,'Ageing Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=4)
	insert aCustomerCentreReportTypes values(4,'Ageing Detailed',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=27)
	insert aCustomerCentreReportTypes values(27,'Ageing Detailed(W/O PDC)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=14)
	insert aCustomerCentreReportTypes values(14,'Ageing Detailed/Type1',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=15)
	insert aCustomerCentreReportTypes values(15,'Out Standing Bills(Billwise Receipt)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=23)
	insert aCustomerCentreReportTypes values(23,'OutStanding Bills/Type1',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=24)
	insert aCustomerCentreReportTypes values(24,'OutStanding Bills/Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=25)
	insert aCustomerCentreReportTypes values(25,'OutStanding Bills/Monthwise',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=21)
	insert aCustomerCentreReportTypes values(21,'Out Standing Bills(Cash Receipt)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=6)
	insert aCustomerCentreReportTypes values(6,'Sales/Collection Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=9)
	insert aCustomerCentreReportTypes values(9,'Collection',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=20)
	insert aCustomerCentreReportTypes values(20,'Collection(W/O Cheque)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=7)
	insert aCustomerCentreReportTypes values(7,'Salesman Transactions',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=10)
	insert aCustomerCentreReportTypes values(10,'Salesman Sales',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=8)
	insert aCustomerCentreReportTypes values(8,'Monthly Analysis',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=11)
	insert aCustomerCentreReportTypes values(11,'Balance Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=12)
	insert aCustomerCentreReportTypes values(12,'Ledger Datewise',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=13)
	insert aCustomerCentreReportTypes values(13,'CostCentre Summary',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=17)
	insert aCustomerCentreReportTypes values(17,'Ledger Billwise',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=18)
	insert aCustomerCentreReportTypes values(18,'Ledger(W/O PDC)',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=19)
	insert aCustomerCentreReportTypes values(19,'All Transactions',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=22)
	insert aCustomerCentreReportTypes values(22,'Sales(Full)/Collection',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=26)
	insert aCustomerCentreReportTypes values(26,'Ledger Detailed',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=28)
	insert aCustomerCentreReportTypes values(28,'Sales/Collection(W/O PDC)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=29)
	insert aCustomerCentreReportTypes values(29,'Salesman Summary',1)

go

if object_id('spGetSalesmanSummary') is not null drop proc spGetSalesmanSummary

go

create proc spGetSalesmanSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null

as


create table #Customer (ID int,Name nvarchar(100),SalesmanId int)
insert #Customer select AccountID,Name,SalesmanId  from invCustomer where @SalesmanID=0 or SalesmanID=@SalesmanID

--Property Filtering
if LEN(@PropertyFilter) > 0
begin
	if OBJECT_ID('vw_CustomerProperty') is not null
	begin
	declare @T1 table (Id int)
	insert @T1 exec
	('
	select t1.AccountID from invCustomer t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
	')
	delete t1 from #Customer t1 
	left outer join @T1 t2 on t1.ID = t2.Id 
	where t2.Id is null
	end
end

--last salesman
;with ls as
(select CustomerId,SalesmanId,ROW_NUMBER()over(partition by CustomerId,SalesmanId order by date desc,no desc)Sno from invSalesHeader)

update c set c.SalesManId=ls.SalesmanId from #Customer c join ls on c.ID=ls.CustomerId and ls.Sno=1

create table #aTransaction(Salesman nvarchar(100),OB float,Qty float,Debit float,Credit float,Profit float)
---------

--Trnasactions
insert #aTransaction(Salesman,OB,Debit,Credit)
select s.Name,case when Date is null or Date<@FromDate then 1 end,sum(case when t.DebtorID=c.ID then Amount end),sum(case when t.CreditorID=c.ID then Amount end) from aTransaction t
join #Customer c on t.DebtorID=c.ID or t.CreditorID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (t.CompanyID=@CompanyID or @CompanyID=0)
and (t.Date<=@ToDate or t.Date is null)
group by s.Name,case when Date is null or Date<@FromDate then 1 end


--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where OB=1


--Qty
insert #aTransaction(Salesman,Qty)
select s.Name,sum(sd.Qty) from invSalesHeader sh
join invSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sh.CustomerID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by s.Name

insert #aTransaction(Salesman,Qty)
select s.Name,sum(sd.Qty) from invMultiSalesHeader sh
join invMultiSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sd.CustomerID=c.ID
left join invSalesMan s on c.SalesmanId=s.Id
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by s.Name

--Profit
exec prBillWiseProfitReport @CompanyId=@CompanyId,@From=@FromDate,@To=@ToDate,@DetailPart=0,@Group=1,@GroupTotal=1,@Columns='',@ValueDataWhereClause='',@MasterDataWhereClause='',@DetailsMasterDataWhereClause='',@Order='',@GrandTotal='',@AlterHeaderTable='',@AlterGroupTable='',@ProcessedValueWhereClause='',@TempTable=''
,@GroupQuery='insert #aTransaction(Salesman,Profit) select [SalesMan],[Profit] from (select 1 sr_no,[SalesMan],sum([Profit]) [Profit] from #BillWiseProfit group by [SalesMan] union all select 2 sr_no,null [SalesMan],sum([Profit]) [Profit] from #BillWiseProfit ) a order by sr_no,[SalesMan]'

;WITH b AS (SELECT TOP (1) * FROM #aTransaction where Profit<>0 ORDER BY Profit desc)
DELETE FROM b
----------


create table #Balance(Salesman nvarchar(100),OB money,Qty float,Debit money,Credit money,CB money,Diff money,Profit money) 
insert #Balance(Salesman,OB,Qty,Debit,Credit,CB,Diff,Profit)
select Salesman,sum(OB),sum(Qty),sum(Debit),sum(Credit)
,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),
sum(isnull(Debit,0)-isnull(Credit,0)),
sum(Profit)
from #aTransaction
group by Salesman

if (@Status=2)
 delete #Balance where CB<=0


declare @Line varchar(25)
set @Line=replicate('-',25) 

--Final
select Salesman,
convert(varchar,OB,4)OB,convert(varchar,Qty,4)Qty,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB,convert(varchar,Diff,4)Diff,convert(varchar,Profit,4)Profit 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Qty),4)Qty,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(CB,0)),4)CB,convert(varchar,sum(isnull(Diff,0)),4)Diff,convert(varchar,sum(isnull(Profit,0)),4)Profit from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line,@Line

go

if object_id('spCustomerBillwiseStatement') is not null drop proc spCustomerBillwiseStatement

go

create proc spCustomerBillwiseStatement
@CompanyID int,
@CustomerID int,
@FromDate int,
@ToDate int


as

set transaction isolation level read uncommitted

declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

declare @Customer table(Id int)

if @CustomerId=0
	insert @Customer select Id from tmpTable where spid=@@spid
else
	insert @Customer 
	select Id from aAccount where Id=@CustomerId or UnderAccountId=@CustomerId

delete tmpTable where spid=@@SPID

declare @aTransaction table(CustomerId int,PeriodId int,[Type] varchar(10),VoucherTypeID int,No int,SNo int,Date int,Age int,PNo int,Debit float,Credit float)


insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,Debit)
select c.Id,PeriodId,VoucherTypeID,No,t.SNo,t.Date,case when CreditorId=c.Id then -1 else 1 end*Amount 
from aTransaction t
join @Customer c on  t.DebtorID=c.Id or t.CreditorID=c.Id
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,0)<=@ToDate


--Advance
insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,Date,Debit)
select c.Id,PeriodId,@VoucherTypeID,No,Date,-Advance from aBillwiseReceiptHdr b
join @Customer c on b.CustomerID=c.Id
where CompanyID=@CompanyID 
and Advance>0
and isnull(Date,0)<=@ToDate


declare @Entries table(PeriodId int,VoucherTypeID int,No int,SNo int,Date int)
insert @Entries(PeriodId,VoucherTypeID,No,SNo,Date)
select distinct PeriodId,VoucherTypeID,No,SNo,Date from @aTransaction

insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,PNo,Credit)
select c.Id,e.PeriodId,e.VoucherTypeID,e.No,e.SNo,h.Date,b.No,b.Paid+isnull(b.Discount,0) from @Entries e
join aBillwiseReceiptDtl b on isnull(e.PeriodId,0)=isnull(b.EPeriodId,0) and isnull(e.VoucherTypeId,0)=isnull(b.EVoucherTypeID,0) and isnull(e.No,0)=isnull(b.ENo,0) and isnull(e.SNo,0)=isnull(b.ESNo,0)
join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No
join @Customer c on h.CustomerID=c.Id
where b.CompanyId=@CompanyId 

declare @ZeroBills table(CustomerId int,PeriodId int,VoucherTypeID int,No int)
insert @ZeroBills 
select CustomerId,PeriodId,VoucherTypeID,No from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,No having round(sum(isnull(Debit,0)-isnull(Credit,0)),2)=0

delete a from @aTransaction a join @ZeroBills b on isnull(a.PeriodId,0)=isnull(b.PeriodId,0) and isnull(a.VoucherTypeID,0)=isnull(b.VoucherTypeID,0) and isnull(a.No,0)=isnull(b.No,0) and a.CustomerId=b.CustomerId

update @aTransaction set PeriodId=null,SNo=null,VoucherTypeId=null,No=null,Date=null,PNo=null where Date<@FromDate

update @aTransaction set Age=datediff(D,cast(cast(Date as varchar) as smalldatetime),current_timestamp) where PNo is null

update @aTransaction set Type=v.Name from @aTransaction t join aVoucherType v on t.VoucherTypeId=v.Id

declare @FD table(CustomerId int,Name nvarchar(100),Address nvarchar(500),VoucherTypeID int,Type varchar(10),No int,PNo int,Salesman nvarchar(100),Date int,DDate int,Age int,Debit float,Credit float)


insert @FD(CustomerId,VoucherTypeID,Type,No,PNo,Date,Age,Debit)
select CustomerId,VoucherTypeID,Type,t.No,t.PNo,Date,Age,isnull(Debit,0)-isnull(Credit,0) from 
(select CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date,max(Age)Age,sum(Debit)Debit,sum(Credit)Credit from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date) t
order by CustomerId,PeriodId,VoucherTypeID,No,SNo,Debit desc

update @FD set Debit=0,Credit=-Debit where Debit<0


--Salesman,Due Date
update t set t.Salesman=s.Name,t.DDate=h.DueDate from invSalesHeader h
join invVoucherTypeDetails v on h.VtypeId=v.Id
join @FD t on h.CompanyId=@CompanyId and h.Date=t.Date and v.AccountVTypeId=t.VoucherTypeID and h.No=t.No
left join invSalesman s on s.Id=h.SalesmanId


--Name
update f set f.Name=c.Name from @FD f join invCustomer c on f.CustomerId=c.AccountID

--Address
update f set f.Address=c.Address1 from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address1)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address2,f.Address+c.Address2) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address2)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address3,f.Address+c.Address3) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address3)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Phone,f.Address+c.Phone) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Phone)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.MobileNo,f.Address+c.MobileNo) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.MobileNo)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Email,f.Address+c.Email) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Email)>0


select CustomerId,Name,Address,Type,No,PNo,Salesman,cast(cast(Date as varchar) as smalldatetime)Date,cast(cast(DDate as varchar) as smalldatetime)DDate,Age,Debit,Credit from @FD

go

if object_id('spSalesmanCustomerBillwiseStatement') is not null drop proc spSalesmanCustomerBillwiseStatement

go

create proc spSalesmanCustomerBillwiseStatement
@CompanyID int,
@SalesmanID int,
@FromDate int,
@ToDate int

as

set transaction isolation level read uncommitted

declare @Bills table(CustomerId int,Name nvarchar(100),Address nvarchar(200),Type varchar(50),No int,PNo int,Salesman nvarchar(100),Date smalldatetime,DDate smalldatetime,Age int,Debit float,Credit float)

insert tmpTable(Id,SPID)
select AccountId,@@SPID from invCustomer where SalesmanId=@SalesmanID or @SalesmanID=0

insert @Bills
exec spCustomerBillwiseStatement @CompanyID=@CompanyID,@CustomerID=0,@FromDate=19000101,@ToDate=@ToDate

select *,isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)CB from 
(
select a.Name,max(case when PNo is null then Date end)Date,Type,No,max(Age)Age,
sum(case when convert(varchar,Date,112)<@FromDate then isnull(Debit,0)-isnull(Credit,0) end) OB,
sum(case when convert(varchar,Date,112) between @FromDate and @ToDate then Debit end) Debit,
sum(case when convert(varchar,Date,112) between @FromDate and @ToDate then Credit end) Credit
from @Bills b join aAccount a on a.Id=b.CustomerId
group by a.Name,Type,No
)a

go

if object_id('spCustomerBillwiseStatement') is not null drop proc spCustomerBillwiseStatement

go

create proc spCustomerBillwiseStatement
@CompanyID int,
@CustomerID int,
@FromDate int,
@ToDate int


as

set transaction isolation level read uncommitted

declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

declare @Customer table(Id int)

if @CustomerId=0
	insert @Customer select Id from tmpTable where spid=@@spid
else
	insert @Customer 
	select Id from aAccount where Id=@CustomerId or UnderAccountId=@CustomerId

delete tmpTable where spid=@@SPID

declare @aTransaction table(CustomerId int,PeriodId int,[Type] varchar(10),VoucherTypeID int,No int,SNo int,Date int,Age int,PNo int,Debit float,Credit float)


insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,Debit)
select c.Id,PeriodId,VoucherTypeID,No,t.SNo,t.Date,case when CreditorId=c.Id then -1 else 1 end*Amount 
from aTransaction t
join @Customer c on  t.DebtorID=c.Id or t.CreditorID=c.Id
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,0)<=@ToDate


--Advance
insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,Date,Debit)
select c.Id,PeriodId,@VoucherTypeID,No,Date,-Advance from aBillwiseReceiptHdr b
join @Customer c on b.CustomerID=c.Id
where CompanyID=@CompanyID 
and Advance>0
and isnull(Date,0)<=@ToDate


declare @Entries table(PeriodId int,VoucherTypeID int,No int,SNo int,Date int)
insert @Entries(PeriodId,VoucherTypeID,No,SNo,Date)
select distinct PeriodId,VoucherTypeID,No,SNo,Date from @aTransaction

insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,PNo,Credit)
select c.Id,e.PeriodId,e.VoucherTypeID,e.No,e.SNo,h.Date,b.No,b.Paid+isnull(b.Discount,0) from @Entries e
join aBillwiseReceiptDtl b on isnull(e.PeriodId,0)=isnull(b.EPeriodId,0) and isnull(e.VoucherTypeId,0)=isnull(b.EVoucherTypeID,0) and isnull(e.No,0)=isnull(b.ENo,0) and isnull(e.SNo,0)=isnull(b.ESNo,0)
join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No
join @Customer c on h.CustomerID=c.Id
where b.CompanyId=@CompanyId 

declare @ZeroBills table(CustomerId int,PeriodId int,VoucherTypeID int,No int)
insert @ZeroBills 
select CustomerId,PeriodId,VoucherTypeID,No from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,No having round(sum(isnull(Debit,0)-isnull(Credit,0)),2)=0

delete a from @aTransaction a join @ZeroBills b on isnull(a.PeriodId,0)=isnull(b.PeriodId,0) and isnull(a.VoucherTypeID,0)=isnull(b.VoucherTypeID,0) and isnull(a.No,0)=isnull(b.No,0) and a.CustomerId=b.CustomerId

update @aTransaction set PeriodId=null,SNo=null,VoucherTypeId=null,No=null,Date=null,PNo=null where Date<@FromDate

update @aTransaction set Age=datediff(D,cast(cast(Date as varchar) as smalldatetime),current_timestamp) where PNo is null

update @aTransaction set Type=v.Name from @aTransaction t join aVoucherType v on t.VoucherTypeId=v.Id

declare @FD table(CustomerId int,Name nvarchar(100),Address nvarchar(500),VoucherTypeID int,
Type varchar(10),No int,PNo int,Salesman nvarchar(100),Date int,DDate int,Age int,Debit float,Credit float,InvoiceFormat varchar(100))


insert @FD(CustomerId,VoucherTypeID,Type,No,PNo,Date,Age,Debit)
select CustomerId,VoucherTypeID,Type,t.No,t.PNo,Date,Age,isnull(Debit,0)-isnull(Credit,0) from 
(select CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date,max(Age)Age,sum(Debit)Debit,sum(Credit)Credit from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date) t
order by CustomerId,PeriodId,VoucherTypeID,No,SNo,Debit desc

update @FD set Debit=0,Credit=-Debit where Debit<0


--Salesman,Due Date
update t set t.Salesman=s.Name,t.DDate=h.DueDate,t.InvoiceFormat=vs.InvoiceFormat from invSalesHeader h
join invVoucherTypeDetails v on h.VtypeId=v.Id
join @FD t on h.CompanyId=@CompanyId and h.Date=t.Date and v.AccountVTypeId=t.VoucherTypeID and h.No=t.No
left join invSalesman s on s.Id=h.SalesmanId
left join invVoucherTypeStartNo VS ON  V.ID=VS.VtypeId  AND h.CompanyId =vs.CompanyId and h.PeriodId=vs.PeriodId 


--Name
update f set f.Name=c.Name from @FD f join invCustomer c on f.CustomerId=c.AccountID

--Address
update f set f.Address=c.Address1 from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address1)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address2,f.Address+c.Address2) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address2)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address3,f.Address+c.Address3) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address3)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Phone,f.Address+c.Phone) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Phone)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.MobileNo,f.Address+c.MobileNo) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.MobileNo)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Email,f.Address+c.Email) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Email)>0


select CustomerId,Name,Address,Type,No,PNo,Salesman,cast(cast(Date as varchar) as smalldatetime)Date,
cast(cast(DDate as varchar) as smalldatetime)DDate,Age,Debit,Credit,InvoiceFormat from @FD

go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete,update,insert
AS
BEGIN
	
	--IF ADDING NEW LINE, NEED TO ADD IN MULTIJOURNAL DISPLAY SP

	SET NOCOUNT ON

	-- Add your code for checking the values from deleted
	Declare @Message varchar(max)	
	if object_id('aBillwiseReceiptDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE RECEIPT : '+ cast(b.No as varchar) from deleted t 
		join aBillwiseReceiptDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.CustomerId or t.DebtorId=h.CustomerId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aChequeClearingDtl') is not null
	Begin
		select @Message='THIS ENTRY HAS REFERENCE IN CHEQUE CLEARING : '+ cast(b.No as varchar) from deleted t 
		join aChequeClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End
	End
	if object_id('aBillwisePaymentDtl') is not null
	Begin
		select @Message=isnull('THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar),'OPENING BALANCE') +' HAS REFERENCE IN BILLWISE PAYMENT : '+ cast(b.No as varchar) from deleted t 
		join aBillwisePaymentDtl b on t.CompanyID=b.CompanyID and isnull(t.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(t.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(t.No,0)=isnull(b.ENo,0)
		join aBillwisePaymentHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No and (t.CreditorId=h.VendorId or t.DebtorId=h.VendorId)
		left join aVoucherType v on t.VoucherTypeId=v.Id
		where t.Amount<>0
		if @Message is not null
		Begin
			ROLLBACK TRANSACTION
			RAISERROR (@Message, 16, 1)    
			--select 1/0 -- to work xact abort on
		End  
	End

	select @Message='THE ENTRY ' + v.Name  + '-'+ cast(t.No as varchar)+' HAS REFERENCE IN CREDIT CARD CLEARING : '+ cast(b.No as varchar) from deleted t 
	join aCreditCardClearingDtl b on t.CompanyID=b.CompanyID and t.PeriodID=b.EPeriodID and t.VoucherTypeID=b.EVTypeID and t.No=b.ENo 
	left join aVoucherType v on t.VoucherTypeId=v.Id
	where t.Amount<>0
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End  
	
	select @Message='DATE IS OUT OF SCOPE OF THE PERIOD : '+ p.Name  from inserted t 
	join aPeriod p on t.PeriodId=p.Id and t.Date not between p.[From] and p.[To]
	if @Message is not null
	Begin
		ROLLBACK TRANSACTION
	    RAISERROR (@Message, 16, 1)    
		--select 1/0 -- to work xact abort on
	End

END

GO

if object_id('spGetCashReceipt') is not null drop proc spGetCashReceipt

go

create proc spGetCashReceipt
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.DebtorID,fh.RepID,isnull(a.Name,'CANCELLED') Debtor,fh.Total,fh.SalesmanID from aCashReceiptHdr fh
left join aAccount a on fh.DebtorID=a.ID
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
Begin

	select fd.No,0 SNo,fd.SNo KSNo,fd.CreditorID,a.Code,a.Name Creditor,fd.CostCentreID,c.Name CostCentre,fd.Description,fd.Amount,fd.Discount,isnull(fd.Amount,0)+isnull(fd.Discount,0) NetAmount from aCashReceiptDtl fd 
	join aAccount a on fd.CreditorID=a.ID 
	left join aCostCentre c on fd.CostCentreID=c.ID
	where fd.CompanyID=@CompanyID and fd.PeriodID=@PeriodID and  fd.No=@No

	declare @ACRAE table(SNo int,PeriodId int,VtypeId int,VType varchar(50),No int,Date int,ESNo int,AccountId int,Account nvarchar(100),Amount float,Paid float,Balance float)

	insert @ACRAE(SNo,PeriodId,VtypeId,No,ESNo,Paid)
	select SNo,EPeriodId,EVoucherTypeId,ENo,ESNo,Paid from aCashReceiptAllotedEntries where CompanyID=@CompanyID and PeriodID=@PeriodID and  No=@No

	update a set a.vtype=v.name from @ACRAE a join aVoucherType v on a.VtypeId=v.ID

	update a set a.Date=t.Date,a.AccountId=case when Paid<0 then t.DebtorID else t.CreditorID end,a.Amount=t.Amount from @ACRAE a join aTransaction t on isnull(a.PeriodId,0)=isnull(t.PeriodID,0) and isnull(a.VtypeId,0)=isnull(t.VoucherTypeID,0) and isnull(a.No,0)=isnull(t.No,0) and isnull(a.ESNo,0)=isnull(t.SNo,0) where t.CompanyId=@CompanyId

	update a set a.Account=ac.name from @ACRAE a join aAccount ac on a.AccountId=ac.ID

	select cast(1 as bit)CHK,* from @ACRAE

End
go

if object_id('spGetCashReceiptDebtors') is not null drop proc spGetCashReceiptDebtors

go

create proc spGetCashReceiptDebtors
as

declare @Account table(Id int,Code nvarchar(50),Name nvarchar(100),Type int)

insert @Account
select a.ID,a.Code,a.Name,cast(case when a.AccountSubGroupID=s.BankAccount then 1 end as bit)CB from aAccount a 
join aSubGroupSettings s on (a.AccountSubGroupID=s.CashInHand or a.AccountSubGroupID=s.BankAccount)

insert @Account
select a.ID,a.Code,a.Name,1 CB from aAccount a 
join aAccountSettings s on a.ID=s.CreditCard

select * from @Account

go

if object_id('spCustomerBillwiseStatement') is not null drop proc spCustomerBillwiseStatement

go

create proc spCustomerBillwiseStatement
@CompanyID int,
@CustomerID int,
@FromDate int,
@ToDate int


as

set transaction isolation level read uncommitted

declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

declare @Customer table(Id int)

if @CustomerId=0
	insert @Customer select Id from tmpTable where spid=@@spid
else
	insert @Customer 
	select Id from aAccount where Id=@CustomerId or UnderAccountId=@CustomerId

delete tmpTable where spid=@@SPID

declare @aTransaction table(CustomerId int,PeriodId int,[Type] varchar(10),VoucherTypeID int,No int,SNo int,Date int,Age int,PNo int,Debit float,Credit float)


insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,Debit)
select c.Id,PeriodId,VoucherTypeID,No,t.SNo,t.Date,case when CreditorId=c.Id then -1 else 1 end*Amount 
from aTransaction t
join @Customer c on  t.DebtorID=c.Id or t.CreditorID=c.Id
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,0)<=@ToDate


--Advance
insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,Date,Debit)
select c.Id,PeriodId,@VoucherTypeID,No,Date,-Advance from aBillwiseReceiptHdr b
join @Customer c on b.CustomerID=c.Id
where CompanyID=@CompanyID 
and Advance>0
and isnull(Date,0)<=@ToDate


declare @Entries table(PeriodId int,VoucherTypeID int,No int,SNo int,Date int)
insert @Entries(PeriodId,VoucherTypeID,No,SNo,Date)
select distinct PeriodId,VoucherTypeID,No,SNo,Date from @aTransaction

insert @aTransaction(CustomerId,PeriodId,VoucherTypeID,No,SNo,Date,PNo,Credit)
select c.Id,e.PeriodId,e.VoucherTypeID,e.No,e.SNo,h.Date,b.No,b.Paid+isnull(b.Discount,0) from @Entries e
join aBillwiseReceiptDtl b on isnull(e.PeriodId,0)=isnull(b.EPeriodId,0) and isnull(e.VoucherTypeId,0)=isnull(b.EVoucherTypeID,0) and isnull(e.No,0)=isnull(b.ENo,0) and isnull(e.SNo,0)=isnull(b.ESNo,0)
join aBillwiseReceiptHdr h on b.CompanyId=h.CompanyId and b.PeriodId=h.PeriodId and b.No=h.No
join @Customer c on h.CustomerID=c.Id
where b.CompanyId=@CompanyId 

declare @ZeroBills table(CustomerId int,PeriodId int,VoucherTypeID int,No int)
insert @ZeroBills 
select CustomerId,PeriodId,VoucherTypeID,No from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,No having round(sum(isnull(Debit,0)-isnull(Credit,0)),2)=0

delete a from @aTransaction a join @ZeroBills b on isnull(a.PeriodId,0)=isnull(b.PeriodId,0) and isnull(a.VoucherTypeID,0)=isnull(b.VoucherTypeID,0) and isnull(a.No,0)=isnull(b.No,0) and a.CustomerId=b.CustomerId

update @aTransaction set PeriodId=null,SNo=null,VoucherTypeId=null,No=null,Date=null,PNo=null where Date<@FromDate

update @aTransaction set Age=datediff(D,cast(cast(Date as varchar) as smalldatetime),current_timestamp) where PNo is null

update @aTransaction set Type=v.Name from @aTransaction t join aVoucherType v on t.VoucherTypeId=v.Id

declare @FD table(CustomerId int,Name nvarchar(100),Address nvarchar(500),VoucherTypeID int,
Type varchar(10),No int,PNo int,Salesman nvarchar(100),Date int,DDate int,Age int,Debit float,Credit float,InvoiceFormat varchar(100))


insert @FD(CustomerId,VoucherTypeID,Type,No,PNo,Date,Age,Debit)
select CustomerId,VoucherTypeID,Type,t.No,t.PNo,Date,Age,isnull(Debit,0)-isnull(Credit,0) from 
(select CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date,max(Age)Age,sum(Debit)Debit,sum(Credit)Credit from @aTransaction group by CustomerId,PeriodId,VoucherTypeID,Type,No,SNo,PNo,Date) t
order by CustomerId,PeriodId,VoucherTypeID,No,SNo,Debit desc

update @FD set Debit=0,Credit=-Debit where Debit<0 and PNo>0


--Salesman,Due Date
update t set t.Salesman=s.Name,t.DDate=h.DueDate,t.InvoiceFormat=vs.InvoiceFormat from invSalesHeader h
join invVoucherTypeDetails v on h.VtypeId=v.Id
join @FD t on h.CompanyId=@CompanyId and h.Date=t.Date and v.AccountVTypeId=t.VoucherTypeID and h.No=t.No
left join invSalesman s on s.Id=h.SalesmanId
left join invVoucherTypeStartNo VS ON  V.ID=VS.VtypeId  AND h.CompanyId =vs.CompanyId and h.PeriodId=vs.PeriodId 


--Name
update f set f.Name=c.Name from @FD f join invCustomer c on f.CustomerId=c.AccountID

--Address
update f set f.Address=c.Address1 from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address1)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address2,f.Address+c.Address2) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address2)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Address3,f.Address+c.Address3) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Address3)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Phone,f.Address+c.Phone) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Phone)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.MobileNo,f.Address+c.MobileNo) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.MobileNo)>0
update f set f.Address=isnull(f.Address + char(13)+char(10)+c.Email,f.Address+c.Email) from @FD f join invCustomer c on f.CustomerId=c.AccountID where len(c.Email)>0


select CustomerId,Name,Address,Type,No,PNo,Salesman,cast(cast(Date as varchar) as smalldatetime)Date,
cast(cast(DDate as varchar) as smalldatetime)DDate,Age,Debit,Credit,InvoiceFormat from @FD

go

if not exists(select 1 from syscolumns where name='SalesmanID' and id=object_id('aChequeReceipt'))
	alter table aChequeReceipt add SalesmanID int foreign key references invSalesman(ID)

	go

if object_id('spGetChequeReceipt') is not null drop proc spGetChequeReceipt

go

create proc spGetChequeReceipt
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.DebtorID,fh.CreditorID,a.Name Debtor,c.Name Creditor,fh.Amount,fh.ChequeNo,cast(cast(fh.ChequeDate as varchar) as smalldatetime)ChequeDate,fh.Description,fh.CostCentreId,fh.SalesmanId from aChequeReceipt fh
join aAccount a on fh.DebtorID=a.ID
join aAccount c on fh.CreditorID=c.ID
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No


go

if OBJECT_ID('spSaveChequeReceipt') is not null drop proc spSaveChequeReceipt

go

create proc spSaveChequeReceipt

@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@CreditorID int,
@Amount float,
@ChequeNo varchar(25),
@ChequeDate int,
@Description nvarchar(100),
@CostCentreId int=null,
@CompanyID int,
@PeriodID int,
@SalesmanId int=null
as

set nocount on

--Duplicate RefNo
declare @Message varchar(100)
select @Message='This Ref.No already given for the Entry No. ' + cast(No as varchar) from aChequeReceipt where RefNo=@RefNo and No<>@No and CompanyID=@CompanyID and PeriodID=@PeriodID and Amount is not null

if @Message is not null
Begin
	select @No No,@Message Message
	return
End


set xact_abort on

Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aChequeReceipt where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aChequeReceipt([No],RefNo,Date,DebtorID,CreditorID,Amount,ChequeNo,ChequeDate,Description,CostCentreId,CompanyID,PeriodID,SalesmanId)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@CreditorID,@Amount,@ChequeNo,@ChequeDate,@Description,nullif(@CostCentreId,0),@CompanyID,@PeriodID,@SalesmanId)
End
else
	update aChequeReceipt set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,CreditorID=@CreditorID,Amount=@Amount,ChequeNo=@ChequeNo,ChequeDate=@ChequeDate,Description=@Description,CostCentreId=nullif(@CostCentreId,0),SalesmanId=nullif(@SalesmanId,0) 
	where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Posting
declare @VoucherTypeID int
select @VoucherTypeID=ChequeReceipt from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

--Amount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,AccountID,CDate,CNo,CostCentreId)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,PDCReceivable,@CreditorID,@Amount,@Description,@RefNo,@DebtorID,@ChequeDate,@ChequeNo,nullif(@CostCentreId,0) from aAccountSettings where CompanyID=@CompanyID


Commit
	
select @No No,@Message Message



go

if object_id('spGetReceiptReport') is not null drop proc spGetReceiptReport

go

create proc spGetReceiptReport
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@CreditorId int,
@SalesmanId int=0,
@CostCentreId int=0

as

declare @Data table(PeriodID int,CompanyID int,No int,RefNo varchar(50),Date smalldatetime,Debtor nvarchar(100),Sno int,Creditor nvarchar(100),
Description nvarchar(300),Amount varchar(25),Discount varchar(25),Total varchar(25))

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

insert @Data(PeriodID,CompanyID,No,RefNo,Date,Debtor,Sno,Creditor,Description,Amount,Discount,Total)
select t2.PeriodID,t2.CompanyID,t1.No,RefNo,cast(cast(Date as varchar) as smalldatetime)Date,ac.Name ,Sno,a.Name ,
Description,Amount,isnull(Discount,0)Discount
,Amount+isnull(Discount,0) Total 
from aCashReceiptDtl t1 join aCashReceiptHdr t2 on t1.No=t2.No and t1.CompanyID=t2.CompanyID and t1.PeriodID=t2.PeriodID
join aAccount a on  t1.CreditorID=a.ID
join aAccount ac on t2.DebtorID=ac.ID
left outer join aCostCentre C on t1.CostCentreID=a.ID
where t2.Date between @FromDate and @ToDate and t2.CompanyID=@CompanyID and t2.PeriodID=@PeriodID
and (@CreditorId=0 or t1.CreditorID=@CreditorId)
and (@SalesmanId=0 or t2.SalesmanId=@SalesmanId)
and (@CostCentreId=0 or t1.CostCentreId=@CostCentreId)
order by No,t1.Sno

select * from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
union all
select null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(CAST( Amount as float)) as money),4),convert(varchar,cast(sum(CAST( Discount as float)) as money),4),convert(varchar,cast(sum(CAST( Total as float)) as money),4) from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
go

if object_id('spGetReceiptReport') is not null drop proc spGetReceiptReport

go

create proc spGetReceiptReport
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@CreditorId int,
@SalesmanId int=0,
@CostCentreId int=0,
@DebtorId int=0

as

declare @Data table(PeriodID int,CompanyID int,No int,RefNo varchar(50),Date smalldatetime,Debtor nvarchar(100),Sno int,Creditor nvarchar(100),
Description nvarchar(300),Amount varchar(25),Discount varchar(25),Total varchar(25))

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

insert @Data(PeriodID,CompanyID,No,RefNo,Date,Debtor,Sno,Creditor,Description,Amount,Discount,Total)
select t2.PeriodID,t2.CompanyID,t1.No,RefNo,cast(cast(Date as varchar) as smalldatetime)Date,ac.Name ,Sno,a.Name ,
Description,Amount,isnull(Discount,0)Discount
,Amount+isnull(Discount,0) Total 
from aCashReceiptDtl t1 join aCashReceiptHdr t2 on t1.No=t2.No and t1.CompanyID=t2.CompanyID and t1.PeriodID=t2.PeriodID
join aAccount a on  t1.CreditorID=a.ID
join aAccount ac on t2.DebtorID=ac.ID
left outer join aCostCentre C on t1.CostCentreID=a.ID
where t2.Date between @FromDate and @ToDate and t2.CompanyID=@CompanyID and t2.PeriodID=@PeriodID
and (@CreditorId=0 or t1.CreditorID=@CreditorId)
and (@SalesmanId=0 or t2.SalesmanId=@SalesmanId)
and (@CostCentreId=0 or t1.CostCentreId=@CostCentreId)
and (@DebtorId=0 or t2.DebtorId=@DebtorId)
order by No,t1.Sno

select * from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
union all
select null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(CAST( Amount as float)) as money),4),convert(varchar,cast(sum(CAST( Discount as float)) as money),4),convert(varchar,cast(sum(CAST( Total as float)) as money),4) from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
go

if OBJECT_ID('spSaveCompany') is not null drop proc spSaveCompany

go

create proc spSaveCompany
@ID int,
@Code nvarchar(25),
@Name nvarchar(50),
@Address nvarchar(300),
@Phone nvarchar(50),
@EMail nvarchar(50),
@AccountID int,
@RegNo nvarchar(50)=null,
@PrintName nvarchar(100)=null
as 

set nocount on

if exists(select 1 from aCompany where ID<>@ID and Code=@Code)
	Begin
	select 1 status ,'Duplicate Code' Message
	return		
	End

if exists(select 1 from aCompany where ID<>@ID and Name=@Name)
	Begin
	select 2 status ,'Duplicate Name' Message
	return		
	End

if exists(select 1 from aCompany where ID<>@ID and AccountID=@AccountID)
	Begin
	select 3 status ,'Duplicate Account' Message
	return		
	End


if @ID=0
Begin
	select @ID=isnull(max(ID),0)+1 from aCompany
	insert aCompany(ID,Code,Name,Address,Phone,EMail,AccountID,RegNo,PrintName)
	values(@ID,@Code,@Name,nullif(@Address,''),nullif(@Phone,''),nullif(@EMail,''),nullif(@AccountID,0),@RegNo,@PrintName)
End
else
	update aCompany set Code=@Code,Name=@Name,Address=nullif(@Address,''),Phone=nullif(@Phone,''),EMail=nullif(@EMail,''),AccountID=nullif(@AccountID,0),RegNo=@RegNo,PrintName=@PrintName where ID=@ID


if object_id('invOption') is not null
Begin
	if not exists(select 1 from invOption where CompanyID=@ID)
		insert invOption(ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,CompanyID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,CompanyTransferCompanyFromId,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces,SalesSerialNoMandatory)
		select top 1 ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,@ID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,@Id,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces,SalesSerialNoMandatory from invOption
	if not exists(select 1 from invOption where CompanyID=@ID)
		insert invOption(CompanyID,ItemCodeLength,QtyDecimalPlaces,DockContent)
		select @ID,5,2,1
End

if object_id('invReportFilter') is not null
Begin
	if not exists(select 1 from invReportFilter where CompanyID=@ID)
	Begin
		declare @ReportID int
		select @ReportID=max(ID) from invReportFilter

		insert invReportFilter(ID,Name,Type,Properties,GroupBy,OrderBy,GroupTotal,ColumnOrder,Summary,SetAsDefault,GroupRow,UserId,CompanyID)
		select @ReportID+ID,Name,Type,Properties,GroupBy,OrderBy,GroupTotal,ColumnOrder,Summary,SetAsDefault,GroupRow,UserId,@ID from invReportFilter
		where CompanyID=(select min(ID) from aCompany)
	End
End


if not exists(select 1 from aAccountSettings where CompanyID=@ID)
	insert aAccountSettings(CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,CompanyID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity,OpeningStock)
	select top 1 CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,@ID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity,OpeningStock from aAccountSettings


if not exists(select 1 from invProjectSettings where CompanyID=@ID)
	insert invProjectSettings(PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,CompanyId)
	select top 1 PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,@ID from invProjectSettings

if object_id('pSettings') is not null
Begin
	if not exists(select 1 from pSettings where CompanyId=@Id)
	Begin
		declare @LastCompanyId int
		select @LastCompanyId=max(CompanyId) from pSettings
		insert pSettings(CompanyID,MergeSameRows,DisplaySalesMan,GridSlNo,GridBarcode,GridUom,GridFoc,StockDisplay,HoldPrintSave,RoundingMethode,ItemSearchBy,ItemSearchType,Key1,Key2,Key3,Key4,PosSales,GridTax,GridTaxP,GridMRP,ItemProperty,ButtonColumnWidth,ProductColumnWidth,CPValidation,CPEncode,HoldCopyPrint,CounterClosingProperty,SalesPrintType,Denomination,SelfShiftClosing,TaxOption,PrintCopy,TaxGroup,GridDisc,GridDiscPercentage,LastRate,DiscountSelection,ProductSearchWindow,PrintMessageOnHold,MaxRateLength,MaxQtyLength,HoldBillPrintType,ProductDetails,CardAndRack,PrintOnF12,GridDescription,PrivilegeCardOption,GridNRate,CreditNote,RateEdit,SalesmanOnPayment,GridSalesman,GridSerialNo,GiftCardAccount,BlockDecimalonQtyEdit,CustomerMobileNo,CostInClosing,ReturnSeparate,CompulsaryNotes,LiveDate,PCardPasswordFocus,GridNativeCaption,OpenCashDrawerOnSave,PrematureDateChange,TimeOffSet)
		select @Id,MergeSameRows,DisplaySalesMan,GridSlNo,GridBarcode,GridUom,GridFoc,StockDisplay,HoldPrintSave,RoundingMethode,ItemSearchBy,ItemSearchType,Key1,Key2,Key3,Key4,PosSales,GridTax,GridTaxP,GridMRP,ItemProperty,ButtonColumnWidth,ProductColumnWidth,CPValidation,CPEncode,HoldCopyPrint,CounterClosingProperty,SalesPrintType,Denomination,SelfShiftClosing,TaxOption,PrintCopy,TaxGroup,GridDisc,GridDiscPercentage,LastRate,DiscountSelection,ProductSearchWindow,PrintMessageOnHold,MaxRateLength,MaxQtyLength,HoldBillPrintType,ProductDetails,CardAndRack,PrintOnF12,GridDescription,PrivilegeCardOption,GridNRate,CreditNote,RateEdit,SalesmanOnPayment,GridSalesman,GridSerialNo,GiftCardAccount,BlockDecimalonQtyEdit,CustomerMobileNo,CostInClosing,ReturnSeparate,CompulsaryNotes,LiveDate,PCardPasswordFocus,GridNativeCaption,OpenCashDrawerOnSave,PrematureDateChange,TimeOffSet from pSettings where CompanyId=@LastCompanyId
	End
End


select 0 status ,'Saved Successfully' Message

go

if object_id('aCustomerCentreReportTypes') is null create table aCustomerCentreReportTypes(ID int,Name varchar(100),Checked bit unique(ID))

go

if not exists(select 1 from aCustomerCentreReportTypes where id=1)
	insert aCustomerCentreReportTypes values(1,'Ledger',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=2)
	insert aCustomerCentreReportTypes values(2,'Sales/Collection',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=5)
	insert aCustomerCentreReportTypes values(5,'Rental/Collection',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=3)
	insert aCustomerCentreReportTypes values(3,'Ageing Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=4)
	insert aCustomerCentreReportTypes values(4,'Ageing Detailed',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=27)
	insert aCustomerCentreReportTypes values(27,'Ageing Detailed(W/O PDC)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=14)
	insert aCustomerCentreReportTypes values(14,'Ageing Detailed/Type1',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=15)
	insert aCustomerCentreReportTypes values(15,'Out Standing Bills(Billwise Receipt)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=23)
	insert aCustomerCentreReportTypes values(23,'OutStanding Bills/Type1',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=24)
	insert aCustomerCentreReportTypes values(24,'OutStanding Bills/Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=25)
	insert aCustomerCentreReportTypes values(25,'OutStanding Bills/Monthwise',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=21)
	insert aCustomerCentreReportTypes values(21,'Out Standing Bills(Cash Receipt)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=6)
	insert aCustomerCentreReportTypes values(6,'Sales/Collection Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=9)
	insert aCustomerCentreReportTypes values(9,'Collection',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=20)
	insert aCustomerCentreReportTypes values(20,'Collection(W/O Cheque)',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=7)
	insert aCustomerCentreReportTypes values(7,'Salesman Transactions',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=10)
	insert aCustomerCentreReportTypes values(10,'Salesman Sales',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=8)
	insert aCustomerCentreReportTypes values(8,'Monthly Analysis',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=11)
	insert aCustomerCentreReportTypes values(11,'Balance Summary',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=12)
	insert aCustomerCentreReportTypes values(12,'Ledger Datewise',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=13)
	insert aCustomerCentreReportTypes values(13,'CostCentre Summary',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=17)
	insert aCustomerCentreReportTypes values(17,'Ledger Billwise',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=18)
	insert aCustomerCentreReportTypes values(18,'Ledger(W/O PDC)',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=19)
	insert aCustomerCentreReportTypes values(19,'All Transactions',1) 
if not exists(select 1 from aCustomerCentreReportTypes where id=22)
	insert aCustomerCentreReportTypes values(22,'Sales(Full)/Collection',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=26)
	insert aCustomerCentreReportTypes values(26,'Ledger Detailed',1)
if not exists(select 1 from aCustomerCentreReportTypes where id=28)
	insert aCustomerCentreReportTypes values(28,'Sales/Collection(W/O PDC)',1)

delete aCustomerCentreReportTypes where id=29
insert aCustomerCentreReportTypes values(29,'Salesman Summary(Billwise Receipt)',1)

go

if object_id('spGetSalesmanSummary') is not null drop proc spGetSalesmanSummary

go

create proc spGetSalesmanSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0

as


create table #aTransaction(Salesman nvarchar(100),Date int,OB float,Qty float,Debit float,Credit float,Profit float)
---------

--Sales
insert #aTransaction(Salesman,Date,Debit)
select s.Name,h.Date,sum(h.NetTotal) from invSalesHeader h
left join invSalesMan s on h.SalesmanId=s.Id
where (h.CompanyID=@CompanyID or @CompanyID=0)
and h.Date<=@ToDate
group by s.Name,h.Date


--Receipt
insert #aTransaction(Salesman,Date,Credit)
select s.Name,h.Date,sum(d.Paid) from aBillwiseReceiptDtl d
join invVoucherTypeDetails vd on d.EVoucherTypeID=vd.AccountVtypeID
join invSalesHeader h on d.CompanyID=h.CompanyId and d.PeriodID=h.PeriodId and vd.VTypeId=h.VtypeId and d.No=h.No
left join invSalesMan s on h.SalesmanId=s.Id
where (h.CompanyID=@CompanyID or @CompanyID=0)
and h.Date<=@ToDate
group by s.Name,h.Date

--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where Date<@FromDate


--Profit
exec prBillWiseProfitReport @CompanyId=@CompanyId,@From=@FromDate,@To=@ToDate,@DetailPart=0,@Group=1,@GroupTotal=1,@Columns='',@ValueDataWhereClause='',@MasterDataWhereClause='',@DetailsMasterDataWhereClause='',@Order='',@GrandTotal='',@AlterHeaderTable='',@AlterGroupTable='',@ProcessedValueWhereClause='',@TempTable=''
,@GroupQuery='insert #aTransaction(Salesman,Profit) select [SalesMan],[Profit] from (select 1 sr_no,[SalesMan],sum([Profit]) [Profit] from #BillWiseProfit group by [SalesMan] union all select 2 sr_no,null [SalesMan],sum([Profit]) [Profit] from #BillWiseProfit ) a order by sr_no,[SalesMan]'

;WITH b AS (SELECT TOP (1) * FROM #aTransaction where Profit<>0 ORDER BY Profit desc)
DELETE FROM b
----------


create table #Balance(Salesman nvarchar(100),OB money,Debit money,Credit money,CB money,Diff money,Profit money) 
insert #Balance(Salesman,OB,Debit,Credit,CB,Diff,Profit)
select Salesman,sum(OB),sum(Debit),sum(Credit)
,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),
sum(isnull(Debit,0)-isnull(Credit,0)),
sum(Profit)
from #aTransaction
group by Salesman


declare @Line varchar(25)
set @Line=replicate('-',25) 

--Final
select Salesman,
convert(varchar,OB,4)OB,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB,convert(varchar,Diff,4)Diff,convert(varchar,Profit,4)Profit 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(CB,0)),4)CB,convert(varchar,sum(isnull(Diff,0)),4)Diff,convert(varchar,sum(isnull(Profit,0)),4)Profit from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line

go

if object_id('spGetSalesmanSummary') is not null drop proc spGetSalesmanSummary

go

create proc spGetSalesmanSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0

as


create table #aTransaction(Salesman nvarchar(100),Date int,OB float,Qty float,Debit float,Credit float,Profit float)
---------

--Sales
insert #aTransaction(Salesman,Date,Debit)
select s.Name,h.Date,sum(h.NetTotal) from invSalesHeader h
left join invSalesMan s on h.SalesmanId=s.Id
where (h.CompanyID=@CompanyID or @CompanyID=0)
and h.Date<=@ToDate
group by s.Name,h.Date


--Receipt
insert #aTransaction(Salesman,Date,Credit)
select s.Name,bh.Date,sum(d.Paid) from aBillwiseReceiptDtl d
join aBillwiseReceiptHdr bh on d.CompanyID=bh.CompanyID and d.PeriodID=bh.PeriodID and d.No=bh.No
join invVoucherTypeDetails vd on d.EVoucherTypeID=vd.AccountVtypeID
join invSalesHeader h on d.CompanyID=h.CompanyId and d.EPeriodID=h.PeriodId and vd.Id=h.VtypeId and d.ENo=h.No
left join invSalesMan s on h.SalesmanId=s.Id
where (bh.CompanyID=@CompanyID or @CompanyID=0)
and bh.Date<=@ToDate
group by s.Name,bh.Date

--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where Date<@FromDate


--Profit
exec prBillWiseProfitReport @CompanyId=@CompanyId,@From=@FromDate,@To=@ToDate,@DetailPart=0,@Group=1,@GroupTotal=1,@Columns='',@ValueDataWhereClause='',@MasterDataWhereClause='',@DetailsMasterDataWhereClause='',@Order='',@GrandTotal='',@AlterHeaderTable='',@AlterGroupTable='',@ProcessedValueWhereClause='',@TempTable=''
,@GroupQuery='insert #aTransaction(Salesman,Profit) select [SalesMan],[Profit] from (select 1 sr_no,[SalesMan],sum([Profit]) [Profit] from #BillWiseProfit group by [SalesMan] union all select 2 sr_no,null [SalesMan],sum([Profit]) [Profit] from #BillWiseProfit ) a order by sr_no,[SalesMan]'

;WITH b AS (SELECT TOP (1) * FROM #aTransaction where Profit<>0 ORDER BY Profit desc)
DELETE FROM b
----------


create table #Balance(Salesman nvarchar(100),OB money,Debit money,Credit money,CB money,Diff money,Profit money) 
insert #Balance(Salesman,OB,Debit,Credit,CB,Diff,Profit)
select Salesman,sum(OB),sum(Debit),sum(Credit)
,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),
sum(isnull(Debit,0)-isnull(Credit,0)),
sum(Profit)
from #aTransaction
group by Salesman


declare @Line varchar(25)
set @Line=replicate('-',25) 

--Final
select Salesman,
convert(varchar,OB,4)OB,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB,convert(varchar,Diff,4)Diff,convert(varchar,Profit,4)Profit 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(CB,0)),4)CB,convert(varchar,sum(isnull(Diff,0)),4)Diff,convert(varchar,sum(isnull(Profit,0)),4)Profit from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line

go

if object_id('spGetSalesmanSummary') is not null drop proc spGetSalesmanSummary

go

create proc spGetSalesmanSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0

as


create table #aTransaction(Salesman nvarchar(100),Date int,OB float,Qty float,Debit float,Credit float,Profit float)
---------

--Sales
insert #aTransaction(Salesman,Date,Debit)
select s.Name,h.Date,sum(h.NetTotal) from invSalesHeader h
left join invSalesMan s on h.SalesmanId=s.Id
where (h.CompanyID=@CompanyID or @CompanyID=0)
and h.Date<=@ToDate
group by s.Name,h.Date


--Sales Return
insert #aTransaction(Salesman,Date,Debit)
select s.Name,h.Date,-sum(h.NetTotal) from invSalesReturnHeader h
left join invSalesMan s on h.SalesmanId=s.Id
where (h.CompanyID=@CompanyID or @CompanyID=0)
and h.Date<=@ToDate
group by s.Name,h.Date


--Receipt
insert #aTransaction(Salesman,Date,Credit)
select s.Name,bh.Date,sum(d.Paid) from aBillwiseReceiptDtl d
join aBillwiseReceiptHdr bh on d.CompanyID=bh.CompanyID and d.PeriodID=bh.PeriodID and d.No=bh.No
join invVoucherTypeDetails vd on d.EVoucherTypeID=vd.AccountVtypeID
join invSalesHeader h on d.CompanyID=h.CompanyId and d.EPeriodID=h.PeriodId and vd.Id=h.VtypeId and d.ENo=h.No
left join invSalesMan s on h.SalesmanId=s.Id
where (bh.CompanyID=@CompanyID or @CompanyID=0)
and bh.Date<=@ToDate
group by s.Name,bh.Date


insert #aTransaction(Salesman,Date,Credit)
select s.Name,bh.Date,sum(d.Paid) from aBillwiseReceiptDtl d
join aBillwiseReceiptHdr bh on d.CompanyID=bh.CompanyID and d.PeriodID=bh.PeriodID and d.No=bh.No
join invVoucherTypeDetails vd on d.EVoucherTypeID=vd.AccountVtypeID
join invSalesReturnHeader h on d.CompanyID=h.CompanyId and d.EPeriodID=h.PeriodId and vd.Id=h.VtypeId and d.ENo=h.No
left join invSalesMan s on h.SalesmanId=s.Id
where (bh.CompanyID=@CompanyID or @CompanyID=0)
and bh.Date<=@ToDate
group by s.Name,bh.Date


--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where Date<@FromDate


--Profit
exec prBillWiseProfitReport @CompanyId=@CompanyId,@From=@FromDate,@To=@ToDate,@DetailPart=0,@Group=1,@GroupTotal=1,@Columns='',@ValueDataWhereClause='',@MasterDataWhereClause='',@DetailsMasterDataWhereClause='',@Order='',@GrandTotal='',@AlterHeaderTable='',@AlterGroupTable='',@ProcessedValueWhereClause='',@TempTable=''
,@GroupQuery='insert #aTransaction(Salesman,Profit) select [SalesMan],[Profit] from (select 1 sr_no,[SalesMan],sum([Profit]) [Profit] from #BillWiseProfit group by [SalesMan] union all select 2 sr_no,null [SalesMan],sum([Profit]) [Profit] from #BillWiseProfit ) a order by sr_no,[SalesMan]'

;WITH b AS (SELECT TOP (1) * FROM #aTransaction where Profit<>0 ORDER BY Profit desc)
DELETE FROM b
----------


create table #Balance(Salesman nvarchar(100),OB money,Debit money,Credit money,CB money,Diff money,Profit money) 
insert #Balance(Salesman,OB,Debit,Credit,CB,Diff,Profit)
select Salesman,sum(OB),sum(Debit),sum(Credit)
,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),
sum(isnull(Debit,0)-isnull(Credit,0)),
sum(Profit)
from #aTransaction
group by Salesman


declare @Line varchar(25)
set @Line=replicate('-',25) 

--Final
select Salesman,
convert(varchar,OB,4)OB,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB,convert(varchar,Diff,4)Diff,convert(varchar,Profit,4)Profit 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(CB,0)),4)CB,convert(varchar,sum(isnull(Diff,0)),4)Diff,convert(varchar,sum(isnull(Profit,0)),4)Profit from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line,@Line

go

if object_id('spGetReceiptReport') is not null drop proc spGetReceiptReport

go

create proc spGetReceiptReport
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@CreditorId int,
@SalesmanId int=0,
@CostCentreId int=0,
@DebtorId int=0

as

declare @Data table(PeriodID int,CompanyID int,No int,RefNo varchar(50),Date smalldatetime,Debtor nvarchar(100),Sno int,Creditor nvarchar(100),
Description nvarchar(300),Amount varchar(25),Discount varchar(25),Total varchar(25))

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

--Cash
insert @Data(PeriodID,CompanyID,No,RefNo,Date,Debtor,Sno,Creditor,Description,Amount,Discount,Total)
select t2.PeriodID,t2.CompanyID,t1.No,RefNo,cast(cast(Date as varchar) as smalldatetime)Date,ac.Name ,Sno,a.Name ,
Description,Amount,isnull(Discount,0)Discount
,Amount+isnull(Discount,0) Total 
from aCashReceiptDtl t1 join aCashReceiptHdr t2 on t1.No=t2.No and t1.CompanyID=t2.CompanyID and t1.PeriodID=t2.PeriodID
join aAccount a on  t1.CreditorID=a.ID
join aAccount ac on t2.DebtorID=ac.ID
left outer join aCostCentre C on t1.CostCentreID=a.ID
where t2.Date between @FromDate and @ToDate and t2.CompanyID=@CompanyID and t2.PeriodID=@PeriodID
and (@CreditorId=0 or t1.CreditorID=@CreditorId)
and (@SalesmanId=0 or t2.SalesmanId=@SalesmanId)
and (@CostCentreId=0 or t1.CostCentreId=@CostCentreId)
and (@DebtorId=0 or t2.DebtorId=@DebtorId)
order by No,t1.Sno



--Cheque
insert @Data(PeriodID,CompanyID,No,RefNo,Date,Debtor,Creditor,Description,Amount,Total)
select t1.PeriodID,t1.CompanyID,t1.No,RefNo,cast(cast(Date as varchar) as smalldatetime)Date,ac.Name,a.Name ,
Description,Amount,Amount Total 
from aChequeReceipt t1 
join aAccount a on  t1.CreditorID=a.ID
join aAccount ac on t1.DebtorID=ac.ID
left outer join aCostCentre C on t1.CostCentreID=a.ID
where t1.Date between @FromDate and @ToDate and t1.CompanyID=@CompanyID and t1.PeriodID=@PeriodID
and (@CreditorId=0 or t1.CreditorID=@CreditorId)
and (@SalesmanId=0 or t1.SalesmanId=@SalesmanId)
and (@CostCentreId=0 or t1.CostCentreId=@CostCentreId)
and (@DebtorId=0 or t1.DebtorId=@DebtorId)
order by No



select * from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
union all
select null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(CAST( Amount as float)) as money),4),convert(varchar,cast(sum(CAST( Discount as float)) as money),4),convert(varchar,cast(sum(CAST( Total as float)) as money),4) from @Data
union all
select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line
go

if object_id('spGetCollections') is not null drop proc spGetCollections

go

create proc spGetCollections
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesManID int=0,
@PropertyFilter nvarchar(max)=null,
@WOC bit=null, --w/o cheque,
@UserID int=null,
@CostCentreId int=0

as
---------------

set transaction isolation level read uncommitted

declare @Account table(ID int,Name nvarchar(100),SalesmanId int,Salesman nvarchar(100))


if nullif(@UserID,0) is not null
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c 
	join invUserCompany uc on c.CompanyID=uc.CompanyID and uc.UserID=@UserID
	left join invSalesman s on c.SalesmanId=s.Id 
	--where (c.CompanyId=@CompanyId or @CompanyId=0)
	where (c.SalesmanId=@SalesmanId or @SalesmanId=0)
else
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c 
	left join invSalesman s on c.SalesmanId=s.Id 
	--where (c.CompanyId=@CompanyId or @CompanyId=0)
	where (c.SalesmanId=@SalesmanId or @SalesmanId=0)


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invCustomer t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from @Account t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null
  end
end 

declare @Line varchar(25)
set @Line=REPLICATE('-',25)

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(200),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where AccountID1 is not null
union
select Id Debtor,0 CD,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.CashInHand


insert @CD 
select DiscountPaid,1,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0

insert @CD 
select Commission,0,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


if isnull(@WOC,0)=0
	insert @CD 
	select a.ID,0,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.BankAccount --where CompanyID=@CompanyID or @CompanyID=0



--Salesman
update c set c.Salesman=s.Name,c.SalesmanId=s.Id from @CD c join invSalesman s on c.Debtor=s.AccountId


declare @BR int
declare @CR int
declare @CC int
declare @BKR int
select @BR=isnull(BillwiseReceipt,0),@CR=isnull(ChequeReceipt,0),@CC=isnull(ChequeClearing,0),@BKR=isnull(BankReceipt,0) from aVoucherTypeSettings

--Cash
insert @Transaction
select t.CompanyId,Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and isnull(t.VoucherTypeID,0) not in(@BR,@CR,@BKR)
group by t.CompanyId,Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null



--Billwise Receipt
insert @Transaction
select t.CompanyID,Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by t.CompanyId,Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name

delete t from @Transaction t
join aChequeClearingHdr cch on t.CompanyId=cch.CompanyID and t.PeriodID=cch.PeriodID and t.No=cch.No 
join aChequeClearingDtl ccd on cch.CompanyID=ccd.CompanyID and cch.PeriodID=ccd.PeriodID and cch.No=ccd.No
where t.VoucherTypeId=@CC and ccd.EVtypeID=@BR
---------------------------

--Cash Sales
insert @Transaction
select t.CompanyId,t.Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Notes,sum(NetTotal),null Discount,v.AccountVtypeId,t.PeriodID,t.SalesmanId,a1.Name
from invSalesHeader t
join invVoucherTypeDetails v on v.ID=t.VtypeId
join aAccount a on a.Id=t.CustomerId
join invOption o on o.CompanyID=@CompanyID
join aAccountSettings st on st.CompanyID=@CompanyID
join aAccount a1 on a1.Id=isnull(o.SalesCashAccountId,st.CashInHand)
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and t.PaymentMode=0
and (t.SalesmanId=@SalesmanId or @SalesmanId=0)
group by t.CompanyId,t.Date,v.Name,t.No,a.Name,s.Name,t.Notes,t.PeriodID,t.SalesmanId,cc.Name,v.AccountVtypeId,a1.Name



if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,CostCentre,VType,No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,CostCentre,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if OBJECT_ID('spSaveCashReceipt') is not null drop proc spSaveCashReceipt

go

create proc spSaveCashReceipt

@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@RepID int=null,
@Total float,
@xml xml,
@xmlBill xml=null,
@CompanyID int,
@PeriodID int,
@UserID int,
@SalesmanId int=null

as

set nocount on


--Duplicate RefNo
declare @Message varchar(100)
select @Message='This Ref.No already given for the Entry No. ' + cast(No as varchar) from aCashReceiptHdr where RefNo=@RefNo and No<>@No and CompanyID=@CompanyID and PeriodID=@PeriodID and Total is not null

if @Message is not null
Begin
	select @No No,@Message Message
	return
End


set xact_abort on
Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aCashReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aCashReceiptHdr([No],RefNo,Date,DebtorID,RepID,Total,CompanyID,PeriodID,UserID,SalesmanId)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@RepID,@Total,@CompanyID,@PeriodID,@UserID,@SalesmanId)
End
else
	update aCashReceiptHdr set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,RepID=@RepID,Total=@Total,UserID=@UserID,SalesmanId=@SalesmanId where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aCashReceiptDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @CashReceiptDtl table(SNo int,CreditorID int,CostCentreID int,Description nvarchar(100),Amount float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @CashReceiptDtl(SNo,CreditorID,CostCentreID,Description,Amount,Discount)
select SNo,CreditorID,nullif(CostCentreID,0),nullif(Description,''),Amount,nullif(Discount,0) from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
CreditorID int '@CreditorID',
CostCentreID int '@CostCentreID',
Description nvarchar(100) '@Description',
Amount float '@Amount',
Discount float '@Discount'
) 
where CreditorID>0
exec sp_xml_removedocument @idoc

insert aCashReceiptDtl(No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,CompanyID,PeriodID)
select @No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,@CompanyID,@PeriodID from @CashReceiptDtl

--aCashReceiptAllotedEntries

delete aCashReceiptAllotedEntries where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

exec sp_xml_preparedocument @idoc output,@xmlBill

insert aCashReceiptAllotedEntries(CompanyId,PeriodId,No,SNo,EPeriodId,EVoucherTypeId,ENo,ESNo,Paid)
select @CompanyId,@PeriodId,@No,Sno,nullif(PeriodId,0),VtypeId,ENo,ESNo,Paid from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
Sno int '@Sno',
PeriodId int '@PeriodId',
VtypeId int '@VtypeId',
ENo int '@No',
ESNo float '@ESNo',
Paid float '@Paid'
) 

exec sp_xml_removedocument @idoc




--Posting
declare @VoucherTypeID int
select @VoucherTypeID=CashReceipt from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

--Amount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,@DebtorID,CreditorID,Amount,isnull(Description,'Cash Received'),@RefNo,CostCentreID from @CashReceiptDtl where Amount<>0

--Discount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,10000+SNo,a.DiscountPaid,CreditorID,Discount,'Discount',@RefNo,CostCentreID from @CashReceiptDtl c,aAccountSettings a where c.Discount<>0 and a.CompanyID=@CompanyID

Commit
	
select @No No,@Message Message



go

if object_id('spGetCreditCardClearing') is not null drop proc spGetCreditCardClearing

go

create proc spGetCreditCardClearing
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,fh.Date,fh.DebtorID,a.Name Debtor,fh.Total from aCreditCardClearingHdr fh
join aAccount a on fh.DebtorID=a.ID
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
	select cast(1 as bit)CHE,cd.Date IntDate,cast(cast(cd.Date as varchar)as smalldatetime)Date,cd.EPeriodID,cd.EVTypeID,v.Name VType,cd.ENo,cd.CardId,c.Name,cd.Amount,cd.Commission,t.Rate TaxP,cd.Tax from aCreditCardClearingDtl cd 
	join aVoucherType v on cd.EVTypeID=v.ID
	join aAccountSettings s on s.CompanyId=@CompanyId
	join aAccount a on s.Commission=a.Id 
	join aTaxGroup t on a.TaxGroupId=t.Id
	left join aCreditCard c on cd.CardID=c.ID
	where cd.CompanyID=@CompanyID and cd.PeriodID=@PeriodID and  cd.No=@No

go

if object_id('spGetCreditCardsForClearing') is not null drop proc spGetCreditCardsForClearing

go

create proc spGetCreditCardsForClearing
@CompanyID int=1,
@FromDate int,
@ToDate int,
@CardID int=null
as

set nocount on
set transaction isolation level read uncommitted

create table #CC(EPeriodID int,VType int,No int,Date int,CardID int,Amount float)

insert #CC (EPeriodID,VType,No,Date,CardID,Amount)
select PeriodID,VoucherTypeID,No,Date,CreditCardID,Amount from aTransaction t
left join aCreditCard c on t.CreditCardID=c.ID
join aAccountSettings s on t.CompanyId=s.CompanyId and (t.DebtorID=s.CreditCard or t.DebtorID=c.AccountID)
where t.CompanyID=@CompanyID 
and (t.CreditCardId=@CardID or @CardID is null)
and Date between @FromDate and @ToDate


--Cleared Cards
insert #CC
select EPeriodID,EVTypeID,ENo,null,CardID,-Amount from aCreditCardClearingDtl where CompanyID=@CompanyID and (CardID=@CardID or @CardID is null)



--Final Selection
create table #FD(EPeriodID int,VType int,No int,Date int,CardID int,Amount float)
insert #FD select EPeriodID,VType,No,null,max(CardID),sum(c1.Amount)Amount from #CC c1 group by EPeriodID,VType,No 
having round(sum(c1.Amount),2)<>0


update f set f.Date=c.Date from #FD f join #CC c on f.EPeriodID=c.EPeriodID and f.Vtype=c.VType and f.No=c.No where c.Date is not null



create table #CCC(CHE bit,EPeriodID int,EVTypeID int,Vtype varchar(50),ENo int,IntDate int,Date smalldatetime,CardId int,Name nvarchar(100),Amount float,Commission float,TaxP float,Tax float)

insert #CCC(CHE,EPeriodID,EVtypeID,Vtype,ENo,IntDate,Date,CardId,Amount)
select cast(1 as bit)CHE,f.EPeriodID,f.VType EVTypeID,v.Name VType,f.No ENo,f.Date IntDate,cast(cast(f.Date as varchar)as smalldatetime)Date, f.CardID,f.Amount from #FD f
join aVoucherType v on f.VType=v.ID
left join aCreditCard c2 on f.CardID=c2.ID
where f.Date is not null

--Commission
update cc set cc.Name=c.Name,cc.Commission=cc.Amount*c.Commission/100 from #CCC cc join aCreditCard c on cc.CardId=c.ID

--Tax
update cc set cc.TaxP=t.Rate,cc.Tax=cc.Commission*t.Rate/100 from #CCC cc 
join aAccountSettings s on s.CompanyId=@CompanyId
join aAccount a on s.Commission=a.Id 
join aTaxGroup t on a.TaxGroupId=t.Id

select * from #CCC


go

