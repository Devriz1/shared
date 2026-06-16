if object_id('spSaveAccountSettings') is not null drop proc spSaveAccountSettings

go

create proc spSaveAccountSettings
@CashInHand int=null,
@Sales int=null,
@Purchase int=null,
@DiscountPaid int=null,
@DiscountReceived int=null,
@Vendors int=null,
@Customers int=null,
@CreditCard int=null,
@Employees int=null,
@ForeignCurrency int=null,
@PDCReceivable int=null,
@PDCPayable int=null,
@InputTax int=null,
@OutputTax int=null,
@Profit int=null,
@Adjustment int=null,
@Commission int=null,
@StockInHand int=null,
@OpeningBalanceEquity int=null,
@OpeningStock int=null,
@CompanyID int
as

delete aAccountSettings where CompanyID=@CompanyID
insert aAccountSettings(CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,PDCReceivable,PDCPayable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity,OpeningStock,CompanyID)
values(@CashInHand,@Sales,@Purchase,@DiscountPaid,@DiscountReceived,@Vendors,@Customers,@CreditCard,@Employees,@ForeignCurrency,@PDCReceivable,@PDCPayable,@InputTax,@OutputTax,@Profit,@Adjustment,@Commission,@StockInHand,@OpeningBalanceEquity,@OpeningStock,@CompanyID)

go

if object_id('spGetCustomers') is not null drop proc spGetCustomers

go

create proc spGetCustomers
@Date int,
@Status tinyint=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@ModuleID tinyint=null,
@UserID int=null,
@SalesManID int=null

as

set nocount on
set xact_abort on

create table #Customer (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),Phone nvarchar(200),Place nvarchar(100),FileNo varchar(50),UnderAccountID int,Balance float)


insert #Customer(ID,Code,Name,UnderAccountID)
select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryDebtors from aSubGroupSettings)


if object_id('invUserCompany') is not null
Begin
	--Delete other company Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		left join aCompany co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		join invUser u on uc.UserId=u.Id
		left join aCompany co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

if object_id('invUserCostCentre') is not null
Begin
	--Delete other CC Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		left join invCostCentre co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUser u on uc.UserId=u.Id
		left join invCostCentre co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

--Default Customer
if object_id('invOption') is not null
Begin
	declare @DefaultCustomer int
	select @DefaultCustomer=DefaultCustomer from invOption where CompanyId=@CompanyId
	if not exists(select 1 from #Customer where Id=@DefaultCustomer)
		insert #Customer(ID,Code,Name,UnderAccountID)
		select Id,Code,Name,UnderAccountID from aAccount where Id=@DefaultCustomer
End


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invAccountPropertyDetails t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from #Customer t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null and t1.UnderAccountID is not null
  end
end 


--Active
if @Status in (0,1)
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
	end
End

--Active + Balance<>0
if @Status=5
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where Inactive=1
	end
End


if object_id('invCustomer') is not null
Begin
	--Company Customers
	insert #Customer(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invCustomer t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Customer cu on t1.AccountId=cu.Id where cu.Id is null
End


if @SalesManID>0
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(SalesManID,0)<>@SalesManID
	end
End


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert #Balance(Level,AccountID) select c1.ID,c1.ID from #Customer c1 left join #Customer c2 on c1.UnderAccountID=c2.ID where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID


--Accounts
update c set c.Balance=b.Balance from #Customer c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from #Customer where id not in(select underaccountid from #Customer where underaccountid is not null)

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join #Customer c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------

--Place
if object_id('invCustomer') is not null
Begin
	update c set c.Place=i.Place,c.FileNo=i.FileNo,c.Phone=trim(i.Phone+'   '+i.MobileNo) from #Customer c join invCustomer i on c.ID=i.AccountID
End

if @Status in(2,5)-- Balance<>0
	delete #Customer where Balance is null or round(Balance,2)=0


if @Status=3-- Balance>Credit Limit
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID and isnull(c.Balance,0)<=ic.CreditLimit
	end
End


if @Status=4-- Balance=0
	delete #Customer where Balance<>0

update #Customer set Name=replace(Name,'"','''')

if not exists(select 1 from #Customer where isnumeric(FileNo)=0 and FileNo is not null)
	select ID,cast(FileNo as int)FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer order by Name
else
	select ID,FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer

go

if OBJECT_ID('spSaveDayBook') is not null drop proc spSaveDayBook

go

create proc spSaveDayBook

@No int,
@RefNo nvarchar(50),
@Date int,
@xml xml,
@PeriodID int
as

set nocount on
set xact_abort on

Begin Transaction
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aDayBookHdr where PeriodID=@PeriodID
	insert aDayBookHdr([No],RefNo,Date,PeriodID)
	values(@No,nullif(@RefNo,''),@Date,@PeriodID)
End
else
	update aDayBookHdr set RefNo=nullif(@RefNo,''),Date=@Date where [No]=@No and PeriodID=@PeriodID


--Details
delete aDayBookDtl where No=@No and PeriodID=@PeriodID

declare @DayBookDtl table(SNo int,CompanyID int,AccountID int,Description nvarchar(100),Qty float,Debit float,Credit float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @DayBookDtl(SNo,CompanyID,AccountID,Description,Qty,Debit,Credit)
select SNo,CompanyID,AccountID,nullif(Description,''),nullif(Qty,0),Debit,Credit from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
CompanyID int '@CompanyID',
AccountID int '@AccountID',
Description nvarchar(100) '@Description',
Qty float '@Qty',
Debit float '@Debit',
Credit float '@Credit'
) 
where CompanyID>0 and AccountID>0

exec sp_xml_removedocument @idoc

insert aDayBookDtl(No,SNo,CompanyID,AccountID,Description,Qty,Debit,Credit,PeriodID)
select @No,SNo,CompanyID,AccountID,Description,Qty,Debit,Credit,@PeriodID from @DayBookDtl

--Posting
declare @VoucherTypeID int
select @VoucherTypeID=DayBook from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and PeriodID=@PeriodID


-- Pls DONT DELETE. ANNA HARSHA MAY USING
-----------------------------------------

--declare @CIH int
--select @CIH=CashInHand from aAccountSettings where CompanyID=1

--insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
--select 1,@PeriodID,@Date,@VoucherTypeID,@No,SNo,@CIH,case when d.CompanyID=1 then d.AccountID else c.AccountID end,Debit,Description,@RefNo from @DayBookDtl d 
--join aCompany c on d.CompanyID=c.ID where d.Debit<>0 

--insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
--select CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,c.AccountID,d.AccountID,Debit,Description,@RefNo from @DayBookDtl d 
--join aCompany c on 1=c.ID where d.Debit<>0 and 1<>CompanyID


--insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
--select 1,@PeriodID,@Date,@VoucherTypeID,@No,SNo,case when d.CompanyID=1 then d.AccountID else c.AccountID end,@CIH,Credit,Description,@RefNo from @DayBookDtl d 
--join aCompany c on d.CompanyID=c.ID where d.Credit<>0 

--insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
--select CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,d.AccountID,c.AccountID,Credit,Description,@RefNo from @DayBookDtl d 
--join aCompany c on 1=c.ID where d.Credit<>0 and 1<>CompanyID


insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
select 1,@PeriodID,@Date,@VoucherTypeID,@No,SNo,d.AccountId,c.AccountID,Debit,Description,@RefNo from @DayBookDtl d 
join aCompany c on d.CompanyID=c.ID where d.Debit<>0 

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
select CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,c.AccountID,d.AccountID,Debit,Description,@RefNo from @DayBookDtl d 
join aCompany c on 1=c.ID where d.Debit<>0 and 1<>CompanyID


insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
select 1,@PeriodID,@Date,@VoucherTypeID,@No,SNo,c.AccountID,d.AccountId,Credit,Description,@RefNo from @DayBookDtl d 
join aCompany c on d.CompanyID=c.ID where d.Credit<>0 

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo)
select CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,d.AccountID,c.AccountID,Credit,Description,@RefNo from @DayBookDtl d 
join aCompany c on 1=c.ID where d.Credit<>0 and 1<>CompanyID


Commit
	
select @No 



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



create table #CCC(CHE bit,EPeriodID int,EVTypeID int,Vtype varchar(50),ENo int,IntDate int,Date smalldatetime,CardId int,Name nvarchar(100),Amount float,Commission float,Tax float)

insert #CCC(CHE,EPeriodID,EVtypeID,Vtype,ENo,IntDate,Date,CardId,Amount)
select cast(1 as bit)CHE,f.EPeriodID,f.VType EVTypeID,v.Name VType,f.No ENo,f.Date IntDate,cast(cast(f.Date as varchar)as smalldatetime)Date, f.CardID,f.Amount from #FD f
join aVoucherType v on f.VType=v.ID
left join aCreditCard c2 on f.CardID=c2.ID
where f.Date is not null

--Commission
update cc set cc.Name=c.Name,cc.Commission=cc.Amount*c.Commission/100 from #CCC cc join aCreditCard c on cc.CardId=c.ID

--Tax
update cc set cc.Tax=cc.Commission*t.Rate/100 from #CCC cc cross join aAccountSettings s join aAccount a on s.Commission=a.Id join aTaxGroup t on a.TaxGroupId=t.Id

select * from #CCC


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
	select row_number() over (order by Date,VoucherTypeId desc,No,SNo),*,null from @Ledger

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


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
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
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(SR as money),@DecimalFormat)SR,convert(varchar,cast(Discount as money),@DecimalFormat)Discount,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,cast(sum(SR) as money),@DecimalFormat),convert(varchar,cast(sum(Discount) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0)-isnull(sum(SR),0)-isnull(sum(Discount),0) as money),@DecimalFormat) from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
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

if object_id('spGetCustomers') is not null drop proc spGetCustomers

go

create proc spGetCustomers
@Date int,
@Status tinyint=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@ModuleID tinyint=null,
@UserID int=null,
@SalesManID int=null

as

set nocount on
set xact_abort on

create table #Customer (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),Phone nvarchar(200),Place nvarchar(100),FileNo varchar(50),UnderAccountID int,Balance float)


insert #Customer(ID,Code,Name,UnderAccountID)
select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryDebtors from aSubGroupSettings)


if object_id('invUserCompany') is not null
Begin
	--Delete other company Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		left join aCompany co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		join invUser u on uc.UserId=u.Id
		left join aCompany co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

if object_id('invUserCostCentre') is not null
Begin
	--Delete other CC Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		left join invSalesman s on c.SalesManId=s.Id
		--join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUserCostCentre uc on COALESCE(c.CostCentreId,s.CostCentreId,0)=isnull(uc.CostCentreId,0)
		left join invCostCentre co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUser u on uc.UserId=u.Id
		left join invCostCentre co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

--Default Customer
if object_id('invOption') is not null
Begin
	declare @DefaultCustomer int
	select @DefaultCustomer=DefaultCustomer from invOption where CompanyId=@CompanyId
	if not exists(select 1 from #Customer where Id=@DefaultCustomer)
		insert #Customer(ID,Code,Name,UnderAccountID)
		select Id,Code,Name,UnderAccountID from aAccount where Id=@DefaultCustomer
End


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invAccountPropertyDetails t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from #Customer t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null and t1.UnderAccountID is not null
  end
end 


--Active
if @Status in (0,1)
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
	end
End

--Active + Balance<>0
if @Status=5
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where Inactive=1
	end
End


if object_id('invCustomer') is not null
Begin
	--Company Customers
	insert #Customer(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invCustomer t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Customer cu on t1.AccountId=cu.Id where cu.Id is null
End


if @SalesManID>0
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(SalesManID,0)<>@SalesManID
	end
End


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert #Balance(Level,AccountID) select c1.ID,c1.ID from #Customer c1 left join #Customer c2 on c1.UnderAccountID=c2.ID where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID


--Accounts
update c set c.Balance=b.Balance from #Customer c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from #Customer where id not in(select underaccountid from #Customer where underaccountid is not null)

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join #Customer c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------

--Place
if object_id('invCustomer') is not null
Begin
	update c set c.Place=i.Place,c.FileNo=i.FileNo,c.Phone=trim(i.Phone+'   '+i.MobileNo) from #Customer c join invCustomer i on c.ID=i.AccountID
End

if @Status in(2,5)-- Balance<>0
	delete #Customer where Balance is null or round(Balance,2)=0


if @Status=3-- Balance>Credit Limit
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID and isnull(c.Balance,0)<=ic.CreditLimit
	end
End


if @Status=4-- Balance=0
	delete #Customer where Balance<>0

update #Customer set Name=replace(Name,'"','''')

if not exists(select 1 from #Customer where isnumeric(FileNo)=0 and FileNo is not null)
	select ID,cast(FileNo as int)FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer order by Name
else
	select ID,FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer

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
@UserID int=null

as
---------------

declare @Account table(ID int,Name nvarchar(100),SalesmanId int,Salesman nvarchar(100))


if nullif(@UserID,0) is not null
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c 
	join invUserCompany uc on c.CompanyID=uc.CompanyID and uc.UserID=@UserID
	left join invSalesman s on c.SalesmanId=s.Id --where (CompanyId=@CompanyId or @CompanyId=0)
else
	insert @Account 
	select c.AccountId,c.Name,c.SalesmanId,s.Name from invCustomer c left join invSalesman s on c.SalesmanId=s.Id where (c.CompanyId=@CompanyId or @CompanyId=0)


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

declare @Transaction table(Date int,VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where (ID=@SalesmanID or @SalesmanID=0) and AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where (ID=@SalesmanID or @SalesmanID=0) and AccountID1 is not null
union
select CashInHand Debtor,0 CD,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


insert @CD 
select DiscountPaid,1,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0

insert @CD 
select Commission,0,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


if isnull(@WOC,0)=0
	insert @CD 
	select a.ID,0,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.BankAccount --where CompanyID=@CompanyID or @CompanyID=0



--Salesman
update c set c.Salesman=s.Name,c.SalesmanId=s.Id from @CD c join invSalesman s on c.Debtor=s.AccountId

--if (@SalesManId>0)
--Begin
--	--delete a from @Account a where isnull(SalesManId,0)<>@SalesManId
--	--delete c from @CD c where isnull(SalesManId,0)<>@SalesManId
--End

--select * from @CD
--select * from @Account

--Cash
insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,isnull(c.SalesMan,a.Salesman),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(c.SalesmanId,a.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
where (t.CompanyID=@CompanyID or @CompanyID=0)
and t.Date between @FromDate and @ToDate
group by Date,v.Name,t.No,a.Name,isnull(c.SalesMan,a.Salesman),t.Description,t.VoucherTypeID,t.PeriodID,isnull(c.SalesmanId,a.SalesmanId),a1.Name
having sum(case when c.CD=0 then Amount end) is not null

if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId

declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,VType, No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if object_id('spGetSalesCollection') is not null drop proc spGetSalesCollection

go

create proc spGetSalesCollection
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int=null,
@OB bit,
@Type tinyint=null

as

declare @SC table(LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,CostCentre nvarchar(50))

insert @SC(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@Type=@Type


if object_id('invSalesDetails') is not null
Begin
	declare @Sales table(LedgerAccountID int,LedgerAccount varchar(100),Date smalldatetime,CompanyID int,VType varchar(50),No int,Account varchar(100),Description varchar(300),Qty float,Debit float,Credit float)	
		
	declare @LedgerAccounts table(LedgerAccountID int)
	insert @LedgerAccounts 
	select distinct LedgerAccountID from @SC

	declare @DSC table(CompanyID int,PeriodID int,VoucherTypeID int,No int)
	insert @DSC select distinct CompanyID int,PeriodID int,VoucherTypeID,No from  @SC

	--Normal Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name + '   ' +cast(d.Rate as varchar),d.Qty,d.Total,case when h.PaymentMode=0 then d.Total end from invSalesDetails d 
	join invSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on d.ProductID=p.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Advance',h.Paid from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Paid<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate and h.PaymentMode=1


	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Discount',case when h.PaymentMode=0 then h.Discount end,h.Discount from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Discount<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Addition',h.Addition,case when h.PaymentMode=0 then h.Addition end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	declare @AdditionCaption varchar(100),@RoundOffCaption varchar(100)
	select @RoundOffCaption=SalesRoundOffCaption from invOption where CompanyID=@CompanyID

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@RoundOffCaption,h.RoundOff,case when h.PaymentMode=0 then h.RoundOff end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.RoundOff<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--Multi Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name,d.Qty,d.Gross,case when h.PaymentMode=0 then d.Gross end from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on h.ProductID=p.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@AdditionCaption,case when h.PaymentMode=0 then abs(d.Addition) end,abs(d.Addition) from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where d.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	;with v as(select distinct vtype from @Sales)
	delete s from @SC s join v on s.VType=v.VType

End

insert @SC(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
select LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit from @Sales

--Company
if @CompanyID=0
	update l set l.Company=c.Name from @SC l join aCompany c on l.CompanyID=c.ID

--Rep Updation
--------------
declare @CRVTypeID int
select @CRVTypeID=CashReceipt from aVoucherTypeSettings

update s set s.Description = isnull(s.Description,'')+rp.Name from @SC s 
join aCashReceiptHdr r on s.VoucherTypeID=@CRVTypeID and s.No=r.No 
join invRep1 rp on r.RepID=rp.ID
where r.CompanyID=@CompanyID and r.PeriodID=@PeriodID
-------------------------------------------

--Balance
declare @SCB table(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount varchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,Balance float,CostCentre nvarchar(50))

insert @SCB
select row_number() over (partition by LedgerAccountID order by LedgerAccountID,Date,Vtype desc,No,Credit),*,null from @sc

;with b as
(select b.Ord,b.LedgerAccountID,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from @SCB b join @SCB s on b.LedgerAccountID=s.LedgerAccountID and s.Ord<=b.Ord group by b.Ord,b.LedgerAccountID)

update s set s.Balance=b.Balance from @SCB s join b on s.LedgerAccountID=b.LedgerAccountID and s.Ord=b.Ord
-----------------


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
	select case when Ord=1 then LedgerAccount end LedgerAccount,Date,VType,No,Account,Description,Debit,Credit,Balance from @SCB
else
Begin
	declare @Line varchar(25)
	set @Line=REPLICATE('-',25)
	select Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,Qty,Debit,Credit,Balance
	from
	(select 0 Ord,Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,cast(Qty as varchar)Qty,convert(varchar,cast(Debit as money),4)Debit,convert(varchar,cast(Credit as money),4)Credit,convert(varchar,cast(Balance as money),4)Balance from @SCB
	union all
	select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	union all
	select 2,null,null,null,null,null,null,null,null,cast(sum(Qty) as varchar),convert(varchar,cast(sum(Debit) as money),4),convert(varchar,cast(sum(Credit) as money),4),null from @SCB
	union all
	select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	)a
	Order by Ord,Date,VoucherTypeId desc,No
End
go

if object_id('spCustomerBalanceSummary') is not null drop proc spCustomerBalanceSummary

go

create proc spCustomerBalanceSummary
@CompanyID int,
@Date int,
@Level tinyint=0,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null
as

set nocount on
set transaction isolation level read uncommitted

create table #Account(ID int,Name nvarchar(100),UnderAccountID int,Level tinyint)

insert #Account(ID,Name,UnderAccountID,Level)
select a.ID,a.Name,a.UnderAccountID,0 from aAccount a
join aAccountSettings s on a.UnderAccountID=s.Customers and a.UnderAccountID<>a.ID
where s.CompanyID=@CompanyID

--Drilling for Under Accounts
while @@rowcount>0
	insert #Account(ID,Name,UnderAccountID,Level)
	select a1.ID,a1.Name,a1.UnderAccountID,a2.Level+1 from aAccount a1 
	join #Account a2 on a1.UnderAccountID=a2.ID 
	left join #Account a3 on a1.ID=a3.ID
	where a3.ID is null



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
	delete t1 from #Account t1 
	left outer join @T1 t2 on t1.ID = t2.Id 
	where t2.Id is null
	end
end 


--TRN
if @Status=6
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(TIN,'')='' and isnull(GST,'')=''
	end
End


declare @Balance table(AccountID int,Account nvarchar(100),Amount float,Level tinyint)

insert @Balance(AccountID,Account,Level,Amount) 
select a.ID,a.Name,a.Level,sum(tr.Amount) from aTransaction tr 
join #Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) and (@CompanyID=0 or tr.CompanyID=@CompanyID)
group by a.ID,a.Name,a.Level


insert @Balance(AccountID,Account,Level,Amount) 
select a.ID,a.Name,a.Level,-sum(tr.Amount) from aTransaction tr 
join #Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) and (@CompanyID=0 or tr.CompanyID=@CompanyID)
group by a.ID,a.Name,a.Level

--Climbing for Levels
while exists(select top 1 1 from @Balance where Level>@Level)
Begin
	update t set t.AccountID=a.UnderAccountID,t.Account=u.Name,t.Level=t.Level-1 from @Balance t join #Account a on t.AccountID=a.ID join #Account u on a.UnderAccountID=u.ID where a.UnderAccountID is not null and t.Level>@Level
End

--Final
declare @Line varchar(25)
set @Line=REPLICATE('-',25)

select Account Customer,c.Address1 Address,c.Place,isnull(c.Phone,c.MobileNo)Phone,isnull(TIN,'')+isnull(GST,'')TRN,convert(varchar,cast(sum(Amount) as money),4) Amount from @Balance b
left join invCustomer c on b.AccountID=c.AccountID
group by Account,Phone,MobileNo,c.Address1,Place,TIN,GST having sum(Amount)<>0
union all
select null,null,null,null,null,@Line
union all
select null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),4) from @Balance
union all
select null,null,null,null,null,@Line

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
@UserID int=null

as
---------------

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

declare @Transaction table(Date int,VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


--insert @CD
--select AccountID Debtor,0 CD,null,null from invSalesman where (ID=@SalesmanID or @SalesmanID=0) and AccountID is not null
--union
--select AccountID1 Debtor,0 CD,null,null from invSalesman where (ID=@SalesmanID or @SalesmanID=0) and AccountID1 is not null
--union
--select CashInHand Debtor,0 CD,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where AccountID1 is not null
union
select CashInHand Debtor,0 CD,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


insert @CD 
select DiscountPaid,1,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0

insert @CD 
select Commission,0,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0


if isnull(@WOC,0)=0
	insert @CD 
	select a.ID,0,null,null from aAccount a join aSubGroupSettings s on a.AccountSubGroupID=s.BankAccount --where CompanyID=@CompanyID or @CompanyID=0



--Salesman
update c set c.Salesman=s.Name,c.SalesmanId=s.Id from @CD c join invSalesman s on c.Debtor=s.AccountId


--if (@SalesManId>0)
--Begin
--	--delete a from @Account a where isnull(SalesManId,0)<>@SalesManId
--	--delete c from @CD c where isnull(SalesManId,0)<>@SalesManId
--End

--select * from @CD
--select * from @Account



--Cash
insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
where (t.CompanyID=@CompanyID or @CompanyID=0)
and t.Date between @FromDate and @ToDate
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name
having sum(case when c.CD=0 then Amount end) is not null


if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,VType, No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if object_id('spCustomersAgeing') is not null drop proc spCustomersAgeing

go

create proc spCustomersAgeing 
@CompanyId int=1,
@ToDate int,
@AccountID int=0,
@Type tinyint, --0 Summary,1 Detailed
@From int=null,
@To int=null,
@SalesmanID int=null,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null

as

  set nocount on
  set transaction isolation level read uncommitted

  create table #Due 
  (SNo int,
   ID numeric ,
   Date int null default 0,
   VtypeID int,
   No int,
   Description nvarchar(200),
   Amount money
  )

  declare @FinalDue table
  (ID numeric ,
   Date int null default 0,
   SNo int,
   Rsales float ,
   TotReceived float ,
   Balance float )


   create table #Account (ID int,Name nvarchar(100),UnderAccountID int,Phone varchar(100))
   insert #Account(Id,Name,UnderAccountId) 
   select a.ID,a.name,a.ID from aAccount a join aSubGroupSettings sg on a.AccountSubGroupID=sg.SundryDebtors where	a.ID=@AccountID

   --Drilling for Under Accounts,
	--while @Type in(1,2) and @@rowcount>0
		insert #Account(Id,Name,UnderAccountId) 
		select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
		join #Account a2 on a1.UnderAccountID=a2.ID 
		left join #Account a3 on a1.ID=a3.ID
		where a3.ID is null
   
	
	if @SalesmanID>0
		delete a from #Account a join invCustomer c on a.ID=c.AccountID where c.SalesmanID<>@SalesmanID or c.SalesmanID is null
 
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
		delete t1 from #Account t1 
		left outer join @T1 t2 on t1.ID = t2.Id 
		where t2.Id is null
	  end
	end 


	--Active
	if @Status in (0,1)
	Begin
		if object_id('invCustomer') is not null
		Begin
			delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
		end
	End
	

  --Phone
  update a set a.Phone=isnull(nullif(c.Phone,''),c.MobileNo) from #Account a join invCustomer c on a.ID=c.AccountID

  /*Amount*/
  insert #Due(SNo,ID,Date,VTypeID,No,Description,Amount) 
  select row_number()over(order by Date,No)SNo, DebtorID,Date,d.VoucherTypeID,isnull(No,0),d.Description,sum(Amount) from aTransaction d 
  join #Account a on a.ID=d.DebtorID 
  where (CompanyID=@CompanyId or @CompanyId=0)
  and (date <= @ToDate or Date is null) 
  group by DebtorID,PeriodID,date,d.VoucherTypeID,d.No,d.Description

  insert @FinalDue (ID,Date,SNo,RSales) 
  select d.ID,dd.date,dd.SNo,sum(d.Amount) from #Due d
  join (select date,SNo,ID from #Due)dd
  on d.ID = dd.ID and d.SNo <= dd.SNo
  group by d.ID,dd.SNo,dd.date

  --Receipts

  declare @aTransaction table(VoucherTypeID int,CNo varchar(50),DebtorId int,CreditorId int,AccountId int,Date int,CompanyId int,Amount float)
  insert @aTransaction
  select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
  from aTransaction d join #Account a on a.id=d.CreditorID where (date <=@ToDate or Date is null) and (CompanyId=@CompanyId or @CompanyId=0)

	if @Type=3 --W/O PDC
	Begin
		declare @CQR int,@CQP int,@CQC int,@BR int,@BP int
		select @CQR=ChequeReceipt,@CQP=ChequePayment,@CQC=ChequeClearing,@BR=BillwiseReceipt,@BP=BillwisePayment from aVoucherTypeSettings
		delete @aTransaction where VoucherTypeID in(@CQR,@CQP,@BR,@BP) and CNo is not null

		insert @aTransaction
		select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
		from aTransaction d join #Account a on a.id=d.AccountID 
		where (date <=@ToDate or Date is null) and (CompanyId=@CompanyId or @CompanyId=0)
		and VoucherTypeID=@CQC

		declare @PDCP int,@PDCR int
		select @PDCP=PDCPayable,@PDCR=PDCReceivable from aAccountSettings 
	
		-- To delete bounced one
		delete @aTransaction where (DebtorID=@PDCP or DebtorID=@PDCR) and CreditorId=@AccountId
		delete @aTransaction where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID=@AccountId
		-----

		update @aTransaction set DebtorID=AccountID,AccountID=null where (DebtorID=@PDCP or DebtorID=@PDCR)
		update @aTransaction set CreditorID=AccountID,AccountID=null where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID<>AccountID
		
	End

  update r set r.totreceived = d.Amount from @FinalDue r join
  (select CreditorID,sum(Amount)Amount from @aTransaction group by CreditorID) d on d.CreditorID = r.ID

  delete from @FinalDue where round(RSales,1) <= round(isnull(TotReceived,0),1)

  delete d from #Due d left join @FinalDue f on d.ID=f.ID and d.SNo=f.SNo where f.SNo is null
  
  if not exists(select * from @FinalDue where RSales>isnull(TotReceived,0)) delete #Due

  update @FinalDue set Balance = RSales - isnull(TotReceived,0)

  declare @MinNo table(ID int,SNo int)
  insert @MinNo select ID,min(SNo) from @FinalDue group by ID

  delete d from #Due d join @MinNo m on d.ID = m.ID and d.SNo < m.SNo
  update d set d.Amount = f.balance from #Due d join @MinNo m on d.ID = m.ID and m.SNo = d.SNo join @FinalDue f on f.ID = m.ID and m.SNo = f.SNo
  ---------------

  --For calculating age, no future date need to consider
  if @ToDate>convert(varchar,current_timestamp,112) 
	  set @ToDate=convert(varchar,current_timestamp,112)


  --Filtering days
  if @From is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<@From 

  if @To is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))>@To
  ----
  
  declare @Line varchar(13)
  set @Line=REPLICATE('_',13)

  declare @AI int
  select @AI=AgeInterval from aOption
  
  declare @1C varchar(max)
  select @1C=cast(@AI+1 as varchar)+'-'+cast(2*@AI as varchar)

  declare @2C varchar(max)
  select @2C=cast(2*@AI+1 as varchar)+'-'+cast(3*@AI as varchar)

  declare @3C varchar(max)
  select @3C=cast(3*@AI+1 as varchar)+'-'+cast(4*@AI as varchar)

  declare @4C varchar(max)
  select @4C=cast(4*@AI+1 as varchar)+'-'
  
  declare @DecimalFormat int
  select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption	

  if @Type in(1,2,3)
  Begin	
	--Balance
	declare @DueBal table(Ord int,ID int,Date int null default 0,VtypeID int,No int,Description nvarchar(200),Amount money,Balance money)
	
	insert @DueBal
    select row_number() over (partition by ID order by ID,Date),ID,Date,VtypeID,No,Description,Amount,null from #Due
	
	
	;with b as
	(select b.Ord,b.id,sum(s.Amount) Balance from @DueBal b join @DueBal s on s.id=b.id and s.Ord<=b.Ord group by b.Ord,b.id)

	update s set s.Balance=b.Balance from @DueBal s join b on b.id=s.id and s.Ord=b.Ord
	---------------------
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)

	Begin
			
		create table #FBal(Ord int,ID int,LedgerAccount nvarchar(100),Date int,VtypeID int,No int,Description nvarchar(100),Amount varchar(50),Age varchar(25),Balance varchar(50),Name nvarchar(100),Days int)

		insert #FBal(Ord,ID,Date,VtypeID,No,Description,Amount,Age,Balance)
		select Ord,ID,Date,VtypeID,No,Description,
		convert(varchar,cast(Amount as money),4),
		datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)),
		convert(varchar,cast(Balance as money),4) from @DueBal

		insert #FBal(Ord,ID,Amount,Balance)
		select max(Ord)+1,ID,@Line,@Line from @DueBal group by ID 

		insert #FBal(Ord,ID,Amount)
		select max(Ord)+2,ID,convert(varchar,cast(sum(Amount) as money),4) from @DueBal group by ID 

		declare @AL int
		select @AL=max(len(Name)) from #Account

		declare @DL int
		select @DL=max(len(Description)) from #FBal

		insert #FBal(LedgerAccount,Ord,ID,Description,Age,Amount,Balance)
		select REPLICATE('_',@AL),max(Ord)+3,ID,REPLICATE('_',@DL),REPLICATE('_',5),@Line,@Line from @DueBal group by ID 

		declare @Address table(ID int,Address nvarchar(100),Ord int)
		insert @Address select ID,c.Name,1 from invCustomer c join #Account a on c.AccountID=a.ID
		insert @Address select ID,c.Address1,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address1)>0 group by ID,c.Address1 
		insert @Address select ID,c.Address2,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address2)>0 group by ID,c.Address2 
		insert @Address select ID,c.Address3,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address3)>0 group by ID,c.Address3 
		insert @Address select ID,c.Place,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Place)>0 group by ID,c.Place
		insert @Address select ID,c.Phone,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Phone)>0 group by ID,c.Phone
		insert @Address select ID,c.MobileNo,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.MobileNo)>0 group by ID,c.MobileNo

		update f set f.LedgerAccount=c.Address from #FBal f join @Address c on f.ID=c.ID and f.Ord=c.Ord where LedgerAccount is null
		
		-- Just for Ordering by Name
		update f set f.Name=a.Name from #Account a join #FBal f on f.ID=a.ID
		
		if @Type in(1,3)
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,Age,Amount,Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
		else
		Begin
			update #FBal set Days=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))
			exec('
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,Amount,
			case when Days <='+@AI+' then Amount end[ 0-'+@AI+'] ,
			case when Days between '+@AI+'+1 and 2*'+@AI+' then Amount end[ '+@1C+'],
			case when Days between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end[ '+@2C+'],
			case when Days between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end[ '+@3C+'],
			case when Days >4*'+@AI+' or Date is null then Amount end[ '+@4C+'],
			Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
			')
		End
	End
	Else
	Begin
		if @Type in(1,3)
		Begin
			select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,convert(varchar,cast(d.Amount as money),@DecimalFormat) Amount,datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))Age,convert(varchar,cast(d.Balance as money),@DecimalFormat)Balance from @DueBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			union all
			select null,null,null,null,null,@Line,null,@Line
			union all
			select null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat),null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat) from @DueBal
			union all
			select null,null,null,null,null,@Line,null,@Line
		End
		Else
		Begin	
			;with a as
			(select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,
			 d.Amount Amount,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<31 then Amount end [ 0-30] ,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 31 and 45 then Amount end [ 31-45],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 46 and 60 then Amount end [ 46-60],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 61 and 90 then Amount end [ 61-90],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) > 90 or Date is null then Amount end [ 90-],
			 d.Balance from @DueBal d 
			 left join aVoucherType v on d.VTypeID=v.ID
			 )

			 select Date,VoucherTypeID,VType,No,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-],convert(varchar,Balance,@DecimalFormat)Balance from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 union all
			 select null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat),convert(varchar,sum([ 0-30]),@DecimalFormat),convert(varchar,sum([ 31-45]),@DecimalFormat),convert(varchar,sum([ 46-60]),@DecimalFormat),convert(varchar,sum([ 61-90]),@DecimalFormat),convert(varchar,sum([ 90-]),@DecimalFormat),null from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 
		End
	End
  End
  Else
  Begin
	  update #Due set Date=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))--,Amount=convert(varchar,Amount,@DecimalFormat)
	  
	  exec
	  ('
	  ;with a as	
	  (select a.Name Account,a.Phone,d.* from 
	  (select ID,
	  sum(case when Date <='+@AI+' then Amount end)[ 0-'+@AI+'] ,
	  sum(case when Date between '+@AI+'+1 and 2*'+@AI+' then Amount end)[ '+@1C+'],
	  sum(case when Date between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end)[ '+@2C+'],
	  sum(case when Date between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end)[ '+@3C+'],
	  sum(case when Date >4*'+@AI+' or Date is null then Amount end)[ '+@4C+'],
	  sum(Amount)Total
	  from #Due group by ID)d
	  join #Account a on a.ID = d.ID)

	  select ID,Account,Phone,convert(varchar,[ 0-'+@AI+'],'+@DecimalFormat+')[ 0-'+@AI+'],convert(varchar,[ '+@1C+'],'+@DecimalFormat+')[ '+@1C+'],convert(varchar,[ '+@2C+'],'+@DecimalFormat+')[ '+@2C+'],convert(varchar,[ '+@3C+'],'+@DecimalFormat+')[ '+@3C+'],convert(varchar,[ '+@4C+'],'+@DecimalFormat+')[ '+@4C+'],convert(varchar,Total,'+@DecimalFormat+')Total from a
	  union all
	  select null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  union all
	  select null,null,null,convert(varchar,sum([ 0-'+@AI+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@1C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@2C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@3C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@4C+']),'+@DecimalFormat+'),convert(varchar,sum(Total),'+@DecimalFormat+') from a
	  union all
	  select null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  ')
  End  

  GO


  if object_id('spGetSalesCollection') is not null drop proc spGetSalesCollection

go

create proc spGetSalesCollection
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int=null,
@OB bit,
@Type tinyint=null

as

declare @SC table(LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,CostCentre nvarchar(50))

insert @SC(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@Type=@Type


if object_id('invSalesDetails') is not null
Begin
	declare @Sales table(LedgerAccountID int,LedgerAccount varchar(100),Date smalldatetime,CompanyID int,VType varchar(50),No int,Account varchar(100),Description varchar(300),Qty float,Debit float,Credit float)	
		
	declare @LedgerAccounts table(LedgerAccountID int)
	insert @LedgerAccounts 
	select distinct LedgerAccountID from @SC

	declare @DSC table(CompanyID int,PeriodID int,VoucherTypeID int,No int)
	insert @DSC select distinct CompanyID int,PeriodID int,VoucherTypeID,No from  @SC

	--Normal Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name + '   ' +cast(d.Rate as varchar),d.Qty,d.Total,case when h.PaymentMode=0 then d.Total end from invSalesDetails d 
	join invSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on d.ProductID=p.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Advance',h.Paid from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Paid<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate and h.PaymentMode=1


	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Discount',case when h.PaymentMode=0 then h.Discount end,h.Discount from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Discount<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Addition',h.Addition,case when h.PaymentMode=0 then h.Addition end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	declare @AdditionCaption varchar(100),@RoundOffCaption varchar(100)
	select @RoundOffCaption=SalesRoundOffCaption from invOption where CompanyID=@CompanyID

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@RoundOffCaption,h.RoundOff,case when h.PaymentMode=0 then h.RoundOff end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.RoundOff<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--Multi Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name,d.Qty,d.Gross,case when h.PaymentMode=0 then d.Gross end from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on h.ProductID=p.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@AdditionCaption,case when h.PaymentMode=0 then abs(d.Addition) end,abs(d.Addition) from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where d.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--;with v as(select distinct vtype from @Sales)
	--delete s from @SC s join v on s.VType=v.VType

	delete s1 from @SC s1 join @Sales s2 on s1.CompanyID=s2.CompanyID and s1.Date=s2.Date and s1.VType=s2.VType and s1.No=s2.No 

End

insert @SC(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
select LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit from @Sales

--Company
if @CompanyID=0
	update l set l.Company=c.Name from @SC l join aCompany c on l.CompanyID=c.ID

--Rep Updation
--------------
declare @CRVTypeID int
select @CRVTypeID=CashReceipt from aVoucherTypeSettings

update s set s.Description = isnull(s.Description,'')+rp.Name from @SC s 
join aCashReceiptHdr r on s.VoucherTypeID=@CRVTypeID and s.No=r.No 
join invRep1 rp on r.RepID=rp.ID
where r.CompanyID=@CompanyID and r.PeriodID=@PeriodID
-------------------------------------------

--Balance
declare @SCB table(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount varchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,Balance float,CostCentre nvarchar(50))

insert @SCB
select row_number() over (partition by LedgerAccountID order by LedgerAccountID,Date,Vtype desc,No,Credit),*,null from @sc

;with b as
(select b.Ord,b.LedgerAccountID,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from @SCB b join @SCB s on b.LedgerAccountID=s.LedgerAccountID and s.Ord<=b.Ord group by b.Ord,b.LedgerAccountID)

update s set s.Balance=b.Balance from @SCB s join b on s.LedgerAccountID=b.LedgerAccountID and s.Ord=b.Ord
-----------------


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
	select case when Ord=1 then LedgerAccount end LedgerAccount,Date,VType,No,Account,Description,Debit,Credit,Balance from @SCB
else
Begin
	declare @Line varchar(25)
	set @Line=REPLICATE('-',25)
	select Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,Qty,Debit,Credit,Balance
	from
	(select 0 Ord,Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,cast(Qty as varchar)Qty,convert(varchar,cast(Debit as money),4)Debit,convert(varchar,cast(Credit as money),4)Credit,convert(varchar,cast(Balance as money),4)Balance from @SCB
	union all
	select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	union all
	select 2,null,null,null,null,null,null,null,null,cast(sum(Qty) as varchar),convert(varchar,cast(sum(Debit) as money),4),convert(varchar,cast(sum(Credit) as money),4),null from @SCB
	union all
	select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	)a
	Order by Ord,Date,VoucherTypeId desc,No
End
go


if object_id('spGetCustomers') is not null drop proc spGetCustomers

go

create proc spGetCustomers
@Date int,
@Status tinyint=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@ModuleID tinyint=null,
@UserID int=null,
@SalesManID int=null

as

set nocount on
set xact_abort on

create table #Customer (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),Phone nvarchar(200),Place nvarchar(100),FileNo varchar(50),UnderAccountID int,Balance float)


insert #Customer(ID,Code,Name,UnderAccountID)
select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryDebtors from aSubGroupSettings)


if object_id('invUserCompany') is not null
Begin
	--Delete other company Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		left join aCompany co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		join invUser u on uc.UserId=u.Id
		left join aCompany co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

if object_id('invUserCostCentre') is not null
Begin
	--Delete other CC Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		left join invSalesman s on c.SalesManId=s.Id
		--join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUserCostCentre uc on COALESCE(c.CostCentreId,s.CostCentreId,0)=isnull(uc.CostCentreId,0)
		left join invCostCentre co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUser u on uc.UserId=u.Id
		left join invCostCentre co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

--Default Customer
if object_id('invOption') is not null
Begin
	declare @DefaultCustomer int
	select @DefaultCustomer=DefaultCustomer from invOption where CompanyId=@CompanyId
	if not exists(select 1 from #Customer where Id=@DefaultCustomer)
		insert #Customer(ID,Code,Name,UnderAccountID)
		select Id,Code,Name,UnderAccountID from aAccount where Id=@DefaultCustomer
End


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invAccountPropertyDetails t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from #Customer t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null and t1.UnderAccountID is not null
  end
end 


--Active
if @Status in (0,1)
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
	end
End

--Active + Balance<>0
if @Status=5
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where Inactive=1
	end
End


if object_id('invCustomer') is not null
Begin
	--Company Customers
	insert #Customer(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invCustomer t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Customer cu on t1.AccountId=cu.Id where cu.Id is null
End


if @SalesManID>0
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(SalesManID,0)<>@SalesManID
	end
End


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert #Balance(Level,AccountID) select c1.ID,c1.ID from #Customer c1 left join #Customer c2 on c1.UnderAccountID=c2.ID where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID


--Accounts
update c set c.Balance=b.Balance from #Customer c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from #Customer where id not in(select underaccountid from #Customer where underaccountid is not null)

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join #Customer c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------

--Place
if object_id('invCustomer') is not null
Begin
	update c set c.Place=i.Place,c.FileNo=i.FileNo,c.Phone=rtrim(ltrim(i.Phone+'   '+i.MobileNo)) from #Customer c join invCustomer i on c.ID=i.AccountID
End

if @Status in(2,5)-- Balance<>0
	delete #Customer where Balance is null or round(Balance,2)=0


if @Status=3-- Balance>Credit Limit
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID and isnull(c.Balance,0)<=ic.CreditLimit
	end
End


if @Status=4-- Balance=0
	delete #Customer where Balance<>0

update #Customer set Name=replace(Name,'"','''')

if not exists(select 1 from #Customer where isnumeric(FileNo)=0 and FileNo is not null)
	select ID,cast(FileNo as int)FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer order by Name
else
	select ID,FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer

go

if object_id('spGridCashBook')  is not null drop proc spGridCashBook

go
  
create proc spGridCashBook 
@FromDate int,
@ToDate int,
@CompanyID int,
@CostCentreId int=0

as  

set nocount on  
set transaction isolation level read uncommitted

Create table #DB  
(Ord tinyint not null default 0, 
 SNo int,
 PeriodId int, 
 Date int null,  
 VoucherTypeId int null,  
 Vtype varchar(50) null,  
 No numeric null,  
 AccountId int null,  
 Account nvarchar(100) null,  
 Description nvarchar(250) null,  
 Debit float null,  
 Credit float null,
 Balance float null)   
 

declare @CIH int
select @CIH=CashInHand from aAccountSettings where CompanyId=@CompanyId

if @CIH is null
	select top 1 @CIH=CashInHand from aAccountSettings order by CompanyId

create table #aTransaction(PeriodId int,Date int,VoucherTypeId int,No int,DebtorId int,CreditorId int,Description nvarchar(500),Amount float,Time datetime)

insert #aTransaction(PeriodId,Date,VoucherTypeId,No,DebtorId,CreditorId,Description,Amount)
select PeriodId,Date,VoucherTypeId,No,DebtorId,CreditorId,Description,Amount from aTransaction
where (CompanyId=@CompanyID or @CompanyID=0)
and (CostCentreId=@CostCentreId or @CostCentreId=0)
and Date between @FromDate and @Todate
and (CreditorId=@CIH  or DebtorId=@CIH)


--Time Updation
if object_id('invAuditTrial') is not null
Begin
	update d set d.Time=a.eventdatetime from #aTransaction d 
	join invAuditTrial a on d.Date=convert(varchar,a.eventdatetime,112) and d.No=a.No 
	join invVoucherTypeDetails v on d.VoucherTypeId=v.AccountVtypeId and a.VtypeId=v.Id
	where a.CompanyId=@CompanyId and a.Action='A'

	update d set d.Time=a.eventdatetime from #aTransaction d 
	join invAuditTrial a on d.Date=convert(varchar,a.eventdatetime,112) and d.No=a.No 
	join aVoucherTypeSettings vt on d.VoucherTypeId=case when a.FormId=52 then vt.CashReceipt when a.FormId=53 then vt.CashPayment end  
	where a.CompanyId=@CompanyId and a.Action='A' and a.VtypeId is null  --and a.FormId in(52,53)
End
------------


insert #DB(Ord,SNo,PeriodId,Date,VoucherTypeId,No,AccountId,Description,Debit)  
select 1,row_number() over (order by Date,Time,DebtorId),v.PeriodID,v.Date,v.VoucherTypeId,v.No,case when v.DebtorId=@CIH then v.CreditorID else v.DebtorId end,ltrim(v.Description),case when v.DebtorId=@CIH then -1 else 1 end* v.Amount from #aTransaction v 

update #DB set Credit=abs(Debit),Debit=null where Debit<0
------------------------------------------
  
--Updations  
update d set d.Vtype=v.Name from #DB d join aVoucherType v on d.VoucherTypeId=v.Id  
update d set d.Account=a.Name from #DB d join aAccount a on d.AccountId=a.Id

--OB  
declare @OB float
select @OB=isnull(@OB,0)+isnull(sum(Amount),0) from aTransaction 
where DebtorId=@CIH 
and (CompanyId=@CompanyID or @CompanyID=0) 
and (CostCentreId=@CostCentreId or @CostCentreId=0)
and (Date<@FromDate  or Date is null)
having isnull(sum(Amount),0)<>0  

select @OB=isnull(@OB,0)-isnull(sum(Amount),0)from aTransaction 
where CreditorId=@CIH 
and (CompanyId=@CompanyID or @CompanyID=0) 
and (CostCentreId=@CostCentreId or @CostCentreId=0)
and (Date<@FromDate  or Date is null)
having isnull(sum(Amount),0)<>0  

select @FromDate=min(Date) from #DB   
insert #DB(SNo,Date,Account,Credit) values(0,@FromDate,'Opening Balance',@OB)  


--Balance
;with b as
(select b.SNo,sum(isnull(s.Credit,0)-isnull(s.Debit,0)) Balance from #DB b join #DB s on s.SNo<=b.SNo group by b.SNo)

update s set s.Balance=b.Balance from #DB s join b on s.SNo=b.SNo
------------------


--Datewise OB  
insert #DB(Date,Account,Credit)  
select t.Date,'Opening Balance',sum(isnull(o.Credit,0)-isnull(o.Debit,0)) from   
(select Distinct Date from #DB) t   
join #DB o on o.Date<t.Date group by t.Date   


--Day Total
insert #DB(Ord,Date,Account,Debit,Credit) select 2,Date,'Day Total',sum(Debit),sum(Credit) from #DB group by Date  

--Closing Balance  
insert #DB(Ord,Date,Account,Credit) select 3,Date,'Closing Balance',sum(isnull(Credit,0)-isnull(Debit,0)) from #DB where Ord<>2 group by Date  

--UnderLine  
insert #DB(Ord,Date) select Distinct 4,Date from #DB  



--Final Selection  
select identity(int,1,1)sno,PeriodId,case when Ord=0 then cast(cast(Date as varchar) as datetime) end Date,  
VoucherTypeId,Vtype,No,AccountId,Account,Description,Debit,Credit,Balance,
case when Ord in(0,2,3) then 1 else 0 end Type  
into #F from #DB d 
order by d.Date,Ord

/*Types  
1-Bold  
2-Description(More Height)*/  
  
declare @w int,@i int,@ml int  
  
set @i=0  
set @w=50  
select @ml=max(len(Description)) from #DB  
 


select 0 Ord,Sno,PeriodId,Date,VoucherTypeId,Vtype,No,AccountId,Account,ltrim(substring(Description,@i*@w+1,@w))Description,cast(Debit as money)Debit,cast(Credit as money)Credit,cast(Balance as money)Balance,Type into #FD from #F  
set @i=@i+1

set identity_insert #FD on  

while @i*@w<@ml  
Begin  
	insert #FD(Ord,Sno,Description,Type) select @i+1,sno,ltrim(substring(Description,@i*@w+1,@w)),2 from #F where ltrim(substring(Description,@i*@w+1,@w))<>''  
	set @i=@i+1  
End   




declare @CashBook table(RI int identity(0,1),PeriodId int,Date smalldatetime,VoucherTypeId int,VType varchar(50),No int,AccountId int,Account nvarchar(100),Description nvarchar(100),Debit varchar(100),Credit varchar(100),Balance varchar(100),Type tinyint)

--declare @DP int
--select @DP=case when DecimalPlaces>2 then 2 else 4 end from aOption

--insert @CashBook 
--select PeriodId,Date,VoucherTypeId,VType,No,AccountId,Account,Description,convert(varchar,Credit,@DP)Debit,convert(varchar,Debit,@DP)Credit,convert(varchar,Balance,@DP)Balance,Type from #FD order by Sno,Ord  
	
 
declare @DP varchar(2)
select @DP='N'+cast(DecimalPlaces as varchar) from aOption

insert @CashBook 
select PeriodId,Date,VoucherTypeId,VType,No,AccountId,Account,Description,Format(Credit,@DP)Debit,Format(Debit,@DP)Credit,FORMAT(Balance,@DP)Balance,Type from #FD order by Sno,Ord  

--Grid  
select * from @CashBook 
  
--Type1  
select RI from @CashBook where Type=1  
  
  
 go

 if object_id('spGetSalesCollection') is not null drop proc spGetSalesCollection

go

create proc spGetSalesCollection
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int=null,
@OB bit,
@Type tinyint=null

as

declare @SC table(LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,CostCentre nvarchar(50))

insert @SC(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@Type=@Type


if object_id('invSalesDetails') is not null
Begin
	declare @Sales table(LedgerAccountID int,LedgerAccount varchar(100),Date smalldatetime,CompanyID int,VType varchar(50),No int,Account varchar(100),Description varchar(300),Qty float,Debit float,Credit float)	
		
	declare @LedgerAccounts table(LedgerAccountID int)
	insert @LedgerAccounts 
	select distinct LedgerAccountID from @SC

	declare @DSC table(CompanyID int,PeriodID int,VoucherTypeID int,No int)
	insert @DSC select distinct CompanyID int,PeriodID int,VoucherTypeID,No from  @SC

	--Normal Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name + '   ' +cast(d.Rate as varchar),d.Qty,d.Total,case when h.PaymentMode=0 then d.Total end from invSalesDetails d 
	join invSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on d.ProductID=p.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Advance',h.Paid from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Paid<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate and h.PaymentMode=1


	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Discount',case when h.PaymentMode=0 then h.Discount end,h.Discount from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Discount<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Addition',h.Addition,case when h.PaymentMode=0 then h.Addition end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	declare @AdditionCaption varchar(100),@RoundOffCaption varchar(100)
	select @RoundOffCaption=SalesRoundOffCaption from invOption where CompanyID=@CompanyID

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@RoundOffCaption,h.RoundOff,case when h.PaymentMode=0 then h.RoundOff end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.RoundOff<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--Multi Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name,d.Qty,d.Gross,case when h.PaymentMode=0 then d.Gross end from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on h.ProductID=p.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@AdditionCaption,case when h.PaymentMode=0 then abs(d.Addition) end,abs(d.Addition) from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where d.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--;with v as(select distinct vtype from @Sales)
	--delete s from @SC s join v on s.VType=v.VType

	delete s1 from @SC s1 join @Sales s2 on s1.CompanyID=s2.CompanyID and s1.Date=s2.Date and s1.VType=s2.VType and s1.No=s2.No 

End

insert @SC(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
select LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit from @Sales

--Company
if @CompanyID=0
	update l set l.Company=c.Name from @SC l join aCompany c on l.CompanyID=c.ID

--Rep Updation
--------------
declare @CRVTypeID int
select @CRVTypeID=CashReceipt from aVoucherTypeSettings

update s set s.Description = isnull(s.Description,'')+rp.Name from @SC s 
join aCashReceiptHdr r on s.VoucherTypeID=@CRVTypeID and s.No=r.No 
join invRep1 rp on r.RepID=rp.ID
where r.CompanyID=@CompanyID and r.PeriodID=@PeriodID
-------------------------------------------

--Balance
declare @SCB table(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount varchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,Balance float,CostCentre nvarchar(50))

insert @SCB
select row_number() over (partition by LedgerAccountID order by LedgerAccountID,Date,VoucherTypeID desc,No),*,null from @sc

;with b as
(select b.Ord,b.LedgerAccountID,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from @SCB b join @SCB s on b.LedgerAccountID=s.LedgerAccountID and s.Ord<=b.Ord group by b.Ord,b.LedgerAccountID)

update s set s.Balance=b.Balance from @SCB s join b on s.LedgerAccountID=b.LedgerAccountID and s.Ord=b.Ord
-----------------


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
	select case when Ord=1 then LedgerAccount end LedgerAccount,Date,VType,No,Account,Description,Debit,Credit,Balance from @SCB
else
Begin
	declare @Line varchar(25)
	set @Line=REPLICATE('-',25)
	select Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,Qty,Debit,Credit,Balance
	from
	(select 0 Ord,Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,cast(Qty as varchar)Qty,convert(varchar,cast(Debit as money),4)Debit,convert(varchar,cast(Credit as money),4)Credit,convert(varchar,cast(Balance as money),4)Balance from @SCB
	union all
	select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	union all
	select 2,null,null,null,null,null,null,null,null,cast(sum(Qty) as varchar),convert(varchar,cast(sum(Debit) as money),4),convert(varchar,cast(sum(Credit) as money),4),null from @SCB
	union all
	select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	)a
	Order by Ord,Date,VoucherTypeId desc,No
End
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
@UserID int=null

as
---------------

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

declare @Transaction table(Date int,VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where AccountID1 is not null
union
--select CashInHand Debtor,0 CD,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0
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


--if (@SalesManId>0)
--Begin
--	--delete a from @Account a where isnull(SalesManId,0)<>@SalesManId
--	--delete c from @CD c where isnull(SalesManId,0)<>@SalesManId
--End

--select * from @Account



--Cash
insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
where (t.CompanyID=@CompanyID or @CompanyID=0)
and t.Date between @FromDate and @ToDate
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name
having sum(case when c.CD=0 then Amount end) is not null


if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,VType, No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go

if object_id('spGetAccountDetails') is not null drop proc spGetAccountDetails

go

create proc spGetAccountDetails
@AccountID int,
@CompanyID int=null,
@PeriodID int=null,
@Date int=99999999
as

declare @Details varchar(100)

--Properties
if object_id('invAccountPropertyDetails') is not null
	select @Details=isnull(@Details,'')+'   '+s.Name from invAccountPropertyDetails pd 
	join invAccountProperty p on pd.PropertyID=p.ID 
	join invAccountSubProperty s on pd.SubPropertyID=s.ID where AccountID=@AccountID

--File No
if object_id('invCustomer') is not null
	select @Details=isnull(@Details,'')+'   '+FileNo from invCustomer where AccountID=@AccountID

--Balance
if @CompanyID is not null and @PeriodID is not null and not exists(select 1 from aAccount where Id=@AccountID and Secret=1)
Begin
	declare @TB table(SGCode varchar(50),SGName nvarchar(100),Code varchar(50),Name varchar(100),NameInOL nvarchar(100),Debit numeric(20,2),Credit numeric(20,2))
	insert @TB
	exec spTrialBalance @CompanyID=@CompanyID,@PeriodID=@PeriodID,@Date=@Date,@AccountID=@AccountID,@Level=1
	select @Details=isnull(@Details,'')+'   '+cast(isnull(Debit,0)-isnull(Credit,0) as varchar) from @TB
End

select @Details Balance

go


if object_id('spGetDayBook') is not null drop proc spGetDayBook

go

create proc spGetDayBook
@No int=null,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date from aDayBookHdr fh
where fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No desc

--Details
if @No is not null
	select fd.No,0 SNo,fd.SNo KSNo,fd.CompanyID,c.Name Company,fd.AccountID,a.Name Account,fd.Description,fd.Qty,fd.Debit,fd.Credit from aDayBookDtl fd 
	join aCompany c on fd.CompanyID=c.ID 
	join aAccount a on fd.AccountID=a.ID 
	where fd.PeriodID=@PeriodID and  fd.No=@No

go

if object_id('spGetCustomerOutstandingBills') is not null drop proc spGetCustomerOutstandingBills

go
create proc spGetCustomerOutstandingBills
@CompanyID int,
@PeriodID int=0,
@CustomerID int=0,
@No int=0,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999,
@PropertyFilter nvarchar(max)=null,
@CostCentreId int=0

as

set transaction isolation level read uncommitted

declare @Customer table(ID int,Name nvarchar(100),UnderAccountID int)

if @CustomerID=0
	insert @Customer(ID)
	select CustomerID from aBillwiseReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
else
	insert @Customer 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@CustomerID


while @Type in(1,2,3,4) and @@rowcount>0
	insert @Customer 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Customer a2 on a1.UnderAccountID=a2.ID 
	left join @Customer a3 on a1.ID=a3.ID
	where a3.ID is null


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
	delete t1 from @Customer t1 
	left outer join @T1 t2 on t1.ID = t2.Id 
	where t2.Id is null
	end
end 


declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

create table #aTransaction(CHK bit,CustomerID int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),BAmount float,Amount float,Paid float,Discount float)


insert #aTransaction(CHK,CustomerID,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,Amount)
select cast(0 as bit),c.ID,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,case when DebtorID=c.ID then CreditorID else DebtorID end,Description,Amount,case when DebtorID=c.ID then 1 else -1 end*Amount from aTransaction t
join @Customer c on (t.DebtorID=c.ID or t.CreditorID=c.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate
and (@CostCentreId=0 or t.CostCentreId=@CostCentreId)

--Advance
insert #aTransaction(CHK,CustomerID,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,Amount)
select cast(0 as bit),c.ID,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,DebtorID,'Advance',-Advance from aBillwiseReceiptHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Customer c on b1.CustomerID=c.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate
and (@CostCentreId=0 or b1.CostCentreId=@CostCentreId)


;with p as
(select CustomerId,EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount from aBillwiseReceiptDtl d
 join aBillwiseReceiptHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)c on d.CompanyID=c.CompanyID and d.PeriodID=c.PeriodID and d.No=c.No
 join @Customer cu on h.CustomerID=cu.ID
 where d.CompanyID=@CompanyID and c.No is null group by CustomerId,EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0) from #aTransaction a join p b on a.CustomerId=b.CustomerId and isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from #aTransaction a join aBillwiseReceiptDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption


if @Type in(1,2,3,4)
Begin
	
	declare @Date smalldatetime
	set @Date=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,CustomerID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(100),Month int,Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money,Debit money,Credit money)
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@CustomerID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			
			insert @T(Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by CustomerID order by CustomerID)Ord,
			CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			
			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else if @Type=2
		Begin
			insert @T(Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by CustomerID order by CustomerID,Date)Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from #aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)Age,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,null,@Line
			
		End
		Else if @Type=3
		Begin
			insert @T(CustomerID,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-],Amount)			
			select CustomerID,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-],
			Amount  
			from #aTransaction where round(Amount,4)<>0

			select c.Name Customer,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-],convert(varchar,sum(Amount),4)Total from @T t
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			group by c.Name
			union all
			select null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-],convert(varchar,sum(Amount),4)Total from @T t
			union all
			select null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else if @Type=4 --Monthwise
		Begin
			insert @T(Ord,CustomerId,PeriodID,Month,Debit,Credit,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by CustomerID order by CustomerID,Month)Ord,* from
			(select CustomerId,PeriodID,Date/100 Month,sum(case when Amount>0 then Amount end)Debit,-sum(case when Amount<0 then Amount end)Credit,sum(Amount)Amount,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end) [ 0-30] ,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end) [ 31-45],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end) [ 46-60],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end) [ 61-90],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end) [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			group by CustomerId,PeriodID,Date/100
			)t

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,Left(Datename(Month,cast(Month*100+1 as varchar)),3)+' - '+substring(cast(Month as varchar),3,2) Month,
			cast(t.Debit as varchar)Debit,
			cast(t.Credit as varchar)Credit,
			cast(t.Amount as varchar)Amount,
			cast([ 0-30] as varchar)[ 0-30],
			cast([ 31-45] as varchar)[ 31-45],
			cast([ 46-60] as varchar)[ 46-60],
			cast([ 61-90] as varchar)[ 61-90],
			cast([ 90-] as varchar)[ 90-]	from @T t
			join @Customer c on t.CustomerID=c.ID
			union all
			select null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,cast(sum(Debit) as varchar),cast(sum(Credit) as varchar),cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
		End
			
	End
	Else
	Begin
		if @Type=1
		Begin
			
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			--order by Date
			
			select PeriodId,Date,VoucherTypeId,VType,No,SNo,Account,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-] from
			(select 0 Ord,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-] from @T t
			 join aAccount a on t.AccountID=a.ID
			 left join aVoucherType v on t.VoucherTypeID=v.ID
			 union all
			 select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			 union all
			 select 2,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat)Amount,convert(varchar,sum([ 0-30]),@DecimalFormat)[ 0-30],convert(varchar,sum([ 31-45]),@DecimalFormat)[ 31-45],convert(varchar,sum([ 46-60]),@DecimalFormat)[ 46-60],convert(varchar,sum([ 61-90]),@DecimalFormat)[ 61-90],convert(varchar,sum([ 90-]),@DecimalFormat)[ 90-] from @t
			 union all
			 select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			)a order by Ord,Date
		End
		Else if @Type=4 --Monthwise
		Begin
			insert @T(PeriodID,Month,Debit,Credit,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,Date/100,sum(case when Amount>0 then Amount end),-sum(case when Amount<0 then Amount end),sum(Amount),
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end) [ 0-30] ,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end) [ 31-45],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end) [ 46-60],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end) [ 61-90],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end) [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			group by PeriodID,Date/100
			
			select t.PeriodID,Left(Datename(Month,cast(Month*100+1 as varchar)),3)+' - '+substring(cast(Month as varchar),3,2) Month,
			cast(t.Debit as varchar)Debit,
			cast(t.Credit as varchar)Credit,
			cast(t.Amount as varchar)Amount,
			cast([ 0-30] as varchar)[ 0-30],
			cast([ 31-45] as varchar)[ 31-45],
			cast([ 46-60] as varchar)[ 46-60],
			cast([ 61-90] as varchar)[ 61-90],
			cast([ 90-] as varchar)[ 90-]	from @T t
			union all
			select null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,cast(sum(Debit) as varchar),cast(sum(Credit) as varchar),cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from #aTransaction 
			where round(Amount,4)<>0
			--order by Date
			
			select PeriodID,Date,VoucherTypeID,VType,No,SNo,Account,Description,Age,Amount from
			(
			select 0 Ord,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)Age,convert(varchar,t.Amount,@DecimalFormat)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select 1,null,null,null,null,null,null,null,null,null,@Line
			union all
			select 2,null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat)Amount from @T t
			union all
			select 3,null,null,null,null,null,null,null,null,null,@Line
			)a order by Ord,Date
		End
	End
End
Else
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.RefNo,t.SNo,a.Name Account,t.Description,t.BAmount,t.Amount,t.Paid,t.Discount,null Balance from #aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,4)<>0
	order by Date,No,SNo desc


go

if object_id('spReceipts') is not null drop proc spReceipts

go


Create proc spReceipts 
@CompanyID int,
@CostCentreId int=0,
@FromDate int,
@ToDate int,
@Level tinyint
as

set nocount on
set transaction isolation level read uncommitted

create table #Debtors(ID int,Name nvarchar(100),NameInOL nvarchar(100))
insert #Debtors
select a.ID,a.Name,a.NameinOL from aAccount a join aSubGroupSettings ss on a.AccountSubGroupID=ss.CashInHand or a.AccountSubGroupID=ss.BankAccount


create table #Creditors(ID int,Name nvarchar(100),NameInOL nvarchar(100),Level nvarchar(100))
insert #Creditors
select a.ID,a.Name,a.NameInOL,a.ID from aAccount a join aSubGroupSettings ss on 
--not (a.AccountSubGroupID=ss.CashInHand or a.AccountSubGroupID=ss.BankAccount) and 
(a.UnderAccountID is null or a.ID=a.UnderAccountID)

declare @space tinyint
set @space=1

while @Level>0
Begin
	insert #Creditors 
	select a.ID,SPACE(@space*7)+a.Name,a.NameInOL,u.Level+'*'+cast(a.ID as varchar) from #Creditors u join aAccount a on u.ID=a.UnderAccountID and a.ID not in(select ID from #Creditors)
	set @Level=@Level-1
	set @space=@space+1
End

create table #FD
(
 DebtorId int,
 Level nvarchar(100),
 AccountID int,
 Account nvarchar(100),
 NameInOL nvarchar(100),
 Balance float,
 Bold bit 
 unique clustered(DebtorId,AccountId)
)

insert #FD(Level,DebtorId,AccountID,Account,NameInOL) 
select c.Level,d.Id,c.ID,c.Name,c.NameInOL from #Creditors c cross join #Debtors d


--Balance
create table #Balance
(
 DebtorId nvarchar(100),
 Level nvarchar(100),
 AccountID int,
 Balance float
 unique clustered(DebtorId,AccountId)
)

insert #Balance(DebtorId,Level,AccountID) 
select d.Id,Level,c.ID from #Creditors c cross join #Debtors d


while @@rowcount>0
	insert #Balance(DebtorId,Level,AccountID)
	select b.DebtorId,b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b join aAccount a on b.AccountID=a.UnderAccountID where a.ID not in(select AccountID from #Balance)

;with b as	
(
 select d.Id DebtorID,t.CreditorId AccountID,sum(Amount) Balance from aTransaction t join #Debtors d on d.ID=t.DebtorId 
 join #Balance c on c.DebtorId=t.DebtorId and c.AccountID=t.CreditorId 
 where (@CompanyID=0 or t.CompanyID=@CompanyID) 
 and (@CostCentreId=0 or t.CostCentreId=@CostCentreId) 
 and (t.Date between @FromDate and @ToDate) group by d.Id,t.CreditorId 
)

 update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.DebtorId=b2.DebtorId and b1.AccountID=b2.AccountID


 --Accounts
 update f set f.Balance=b.Balance from #FD f join #Balance b on f.DebtorId=b.DebtorId and f.AccountID=b.AccountID

 
 --Levels
;with b as (select * from #Balance where Balance is not null)
,lb as
(select b1.DebtorId,b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b1.DebtorId=b2.DebtorId and  b2.level+'*' like b1.level+'*%' group by b1.DebtorId,b1.level)

update f set f.Balance=l.Balance from #FD f join lb l on f.DebtorId=l.DebtorId and f.Level=l.Level
--

delete #FD where Balance is null

--Bold
update f1 set f1.Bold=1 from #FD f1 join #FD f2 on f2.level like f1.level+'*%' 


select * from 
(
select 'RECEIPTS'[Group],d.Name CashBank,Account,f.NameInOL,Balance,Level,Bold,case when Level like '%*%' then 1 end Child from #FD f join #Debtors d on f.DebtorId=d.Id

union all 

select 'OPENING BALANCE' [Group],null,a.Name Particluars,NameInOL,
sum(case when a.ID=t.CreditorID then -1 else 1 end* t.Amount)Amount,'A',null,null from aTransaction t
join #Debtors a on (a.ID=t.CreditorID or a.ID=t.DebtorID)
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and (@CostCentreId=0 or t.CostCentreId=@CostCentreId)  
and (t.Date<@FromDate or t.Date is null)
and (t.DebtorId<>t.CreditorId)
group by a.Name,a.NameInOL
having round(sum(case when a.ID=t.DebtorId then -1 else 1 end* t.Amount),2)<>0
)f
order by Level

GO

if object_id('spPayments') is not null drop proc spPayments

go


Create proc spPayments 
@CompanyID int,
@CostCentreId int=0,
@FromDate int,
@ToDate int,
@Level tinyint
as

set nocount on
set transaction isolation level read uncommitted

create table #Creditors(ID int,Name nvarchar(100),NameInOL nvarchar(100))
insert #Creditors
select a.ID,a.Name,a.NameInOL from aAccount a join aSubGroupSettings ss on a.AccountSubGroupID=ss.CashInHand or a.AccountSubGroupID=ss.BankAccount


create table #Debtors(ID int,Name nvarchar(100),NameInOL nvarchar(100),Level nvarchar(100))
insert #Debtors
select a.ID,a.Name,a.NameInOL,a.ID from aAccount a join aSubGroupSettings ss on 
--not (a.AccountSubGroupID=ss.CashInHand or a.AccountSubGroupID=ss.BankAccount) and 
(a.UnderAccountID is null or a.ID=a.UnderAccountID)

declare @space tinyint
set @space=1

while @Level>0
Begin
	insert #Debtors 
	select a.ID,SPACE(@space*7)+a.Name,a.NameInOL,u.Level+'*'+cast(a.ID as varchar) from #Debtors u join aAccount a on u.ID=a.UnderAccountID and a.ID not in(select ID from #Debtors)
	set @Level=@Level-1
	set @space=@space+1
End

create table #FD
(
 CreditorId int,
 Level nvarchar(100),
 AccountID int,
 Account nvarchar(100),
 NameInOL nvarchar(100),
 Balance float,
 Bold bit
 unique clustered(CreditorId,AccountId)
)

insert #FD(Level,CreditorId,AccountID,Account,NameInOL) 
select d.Level,c.Id,d.ID,d.Name,d.NameInOL from #Debtors d cross join #Creditors c


--Balance
create table #Balance
(
 CreditorId nvarchar(100),
 Level nvarchar(100),
 AccountID int,
 Balance float
 unique clustered(CreditorId,AccountId)
)


insert #Balance(CreditorId,Level,AccountID) 
select c.Id,Level,d.ID from #Debtors d cross join #Creditors c

while @@rowcount>0
	insert #Balance(CreditorId,Level,AccountID)
	select b.CreditorId,b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b join aAccount a on b.AccountID=a.UnderAccountID where a.ID not in(select AccountID from #Balance)

;with b as	
(
 select c.Id CreditorId,t.DebtorID AccountID,sum(Amount) Balance from aTransaction t join #Creditors c on c.ID=t.CreditorID 
 join #Balance d on d.CreditorId=t.CreditorId and d.AccountID=t.DebtorID 
 where (@CompanyID=0 or t.CompanyID=@CompanyID) 
 and (@CostCentreId=0 or t.CostCentreId=@CostCentreId) 
 and (t.Date between @FromDate and @ToDate) group by c.Id,t.DebtorID 
)

 update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.CreditorId=b2.CreditorId and b1.AccountID=b2.AccountID

 --Accounts
 update f set f.Balance=b.Balance from #FD f join #Balance b on f.CreditorId=b.CreditorId and f.AccountID=b.AccountID

 
 --Levels
;with b as (select * from #Balance where Balance is not null)
,lb as
(select b1.CreditorId,b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b1.CreditorId=b2.CreditorId and  b2.level+'*' like b1.level+'*%' group by b1.CreditorId,b1.level)

update f set f.Balance=l.Balance from #FD f join lb l on f.CreditorId=l.CreditorId and f.Level=l.Level
--

delete #FD where Balance is null

--Bold
update f1 set f1.Bold=1 from #FD f1 join #FD f2 on f2.level like f1.level+'*%' 


select * from 
(
select 'PAYMENTS'[Group],c.Name CashBank,Account,f.NameInOL,Balance,Level,Bold,case when Level like '%*%' then 1 end Child from #FD f join #Creditors c on f.CreditorId=c.Id

union all 

select 'CLOSING BALANCE' [Group],null,a.Name Particluars,NameInOL,
sum(case when a.ID=t.CreditorID then -1 else 1 end* t.Amount)Amount,'A',null,null from aTransaction t
join #Creditors a on (a.ID=t.DebtorID or a.ID=t.CreditorID)
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and (@CostCentreId=0 or t.CostCentreId=@CostCentreId)  
and (t.Date<=@ToDate or t.Date is null)
and (t.DebtorId<>t.CreditorId)
group by a.Name,a.NameInOL
having round(sum(case when a.ID=t.CreditorID then -1 else 1 end* t.Amount),2)<>0
)f
order by Level

GO

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

declare @Transaction table(Date int,VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

--Cash+Discount
declare @CD table(Debtor int,CD bit,Salesman nvarchar(100),SalesmanId int)


insert @CD
select AccountID Debtor,0 CD,null,null from invSalesman where AccountID is not null
union
select AccountID1 Debtor,0 CD,null,null from invSalesman where AccountID1 is not null
union
--select CashInHand Debtor,0 CD,null,null from aAccountSettings where CompanyID=@CompanyID or @CompanyID=0
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


--Cash
insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name
having sum(case when c.CD=0 then Amount end) is not null


if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,VType, No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if object_id('spGetCustomers') is not null drop proc spGetCustomers

go

create proc spGetCustomers
@Date int,
@Status tinyint=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@ModuleID tinyint=null,
@UserID int=null,
@SalesManID int=null

as

set nocount on
set xact_abort on

create table #Customer (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),Phone nvarchar(200),Place nvarchar(100),FileNo varchar(50),UnderAccountID int,Balance float)


insert #Customer(ID,Code,Name,UnderAccountID)
select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryDebtors from aSubGroupSettings)


if object_id('invUserCompany') is not null
Begin
	--Delete other company Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		left join aCompany co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		join invUser u on uc.UserId=u.Id
		left join aCompany co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

if object_id('invUserCostCentre') is not null
Begin
	--Delete other CC Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		left join invSalesman s on c.SalesManId=s.Id
		--join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUserCostCentre uc on COALESCE(c.CostCentreId,s.CostCentreId,0)=isnull(uc.CostCentreId,0)
		left join invCostCentre co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUser u on uc.UserId=u.Id
		left join invCostCentre co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

--Default Customer
if object_id('invOption') is not null
Begin
	declare @DefaultCustomer int
	select @DefaultCustomer=DefaultCustomer from invOption where CompanyId=@CompanyId
	if not exists(select 1 from #Customer where Id=@DefaultCustomer)
		insert #Customer(ID,Code,Name,UnderAccountID)
		select Id,Code,Name,UnderAccountID from aAccount where Id=@DefaultCustomer
End


if LEN(@PropertyFilter) > 0
begin
  if OBJECT_ID('vw_CustomerProperty') is not null
  begin
    declare @T1 table (Id int)
    insert @T1 exec
    ('
    select t1.AccountID from invAccountPropertyDetails t1
	join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
	where ' + @PropertyFilter + '
    ')
    delete t1 from #Customer t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null and t1.UnderAccountID is not null
  end
end 


--Active
if @Status in (0,1)
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
	end
End

--Active + Balance<>0
if @Status=5
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where Inactive=1
	end
End


if object_id('invCustomer') is not null
Begin
	--Company Customers
	insert #Customer(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invCustomer t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Customer cu on t1.AccountId=cu.Id where cu.Id is null
End


if @SalesManID>0
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(SalesManID,0)<>@SalesManID
	end
End


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert #Balance(Level,AccountID) select c1.ID,c1.ID from #Customer c1 left join #Customer c2 on c1.UnderAccountID=c2.ID where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID


--Accounts
update c set c.Balance=b.Balance from #Customer c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from #Customer where id not in(select underaccountid from #Customer where underaccountid is not null)

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join #Customer c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------

--Place
if object_id('invCustomer') is not null
Begin
	update c set c.Place=i.Place,c.FileNo=i.FileNo,c.Phone=rtrim(ltrim(isnull(i.Phone,'')+'   '+isnull(i.MobileNo,''))) from #Customer c join invCustomer i on c.ID=i.AccountID
End

if @Status in(2,5)-- Balance<>0
	delete #Customer where Balance is null or round(Balance,2)=0


if @Status=3-- Balance>Credit Limit
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID and isnull(c.Balance,0)<=ic.CreditLimit
	end
End


if @Status=4-- Balance=0
	delete #Customer where Balance<>0

update #Customer set Name=replace(Name,'"','''')

if not exists(select 1 from #Customer where isnumeric(FileNo)=0 and FileNo is not null)
	select ID,cast(FileNo as int)FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer order by Name
else
	select ID,FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer

go

if object_id('spGetChequeClearing') is not null drop proc spGetChequeClearing

go

create proc spGetChequeClearing
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.Bounce,fh.CostCentreId from aChequeClearingHdr fh
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
	select cast(1 as bit)CHE,Type,cd.EPeriodID,cd.EVTypeID,v.Name VType,cd.ENo,cast(cast(t.Date as varchar)as smalldatetime)Date,t.CNo,cast(cast(t.CDate as varchar)as smalldatetime)CDate,t.AccountID BankID,b.Name Bank,a.ID AccountID,a.Name Account,t.Description,t.Amount,cd.Commission 
	from aChequeClearingDtl cd 
	join aVoucherType v on cd.EVTypeID=v.ID
	join aTransaction t on cd.CompanyID=t.CompanyID and cd.EPeriodID=t.PeriodID and cd.EVtypeID=t.VoucherTypeID and cd.ENo=t.No
	join aAccount b on t.AccountID=b.ID
	cross join aVoucherTypeSettings vs
	join aAccount a on case when vs.ChequeReceipt=cd.EVtypeID then t.CreditorID else t.DebtorID end=a.ID
	where cd.CompanyID=@CompanyID and cd.PeriodID=@PeriodID and  cd.No=@No

go

if object_id('spCustomersAgeing') is not null drop proc spCustomersAgeing

go

create proc spCustomersAgeing 
@CompanyId int=1,
@ToDate int,
@AccountID int=0,
@Type tinyint, --0 Summary,1 Detailed
@From int=null,
@To int=null,
@SalesmanID int=null,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null,
@CostCentreId int=0

as

  set nocount on
  set transaction isolation level read uncommitted

  create table #Due 
  (SNo int,
   ID numeric ,
   Date int null default 0,
   VtypeID int,
   No int,
   Description nvarchar(200),
   Amount money
  )

  declare @FinalDue table
  (ID numeric ,
   Date int null default 0,
   SNo int,
   Rsales float ,
   TotReceived float ,
   Balance float )


   create table #Account (ID int,Name nvarchar(100),UnderAccountID int,Phone varchar(100))
   insert #Account(Id,Name,UnderAccountId) 
   select a.ID,a.name,a.ID from aAccount a join aSubGroupSettings sg on a.AccountSubGroupID=sg.SundryDebtors where	a.ID=@AccountID

   --Drilling for Under Accounts,
	--while @Type in(1,2) and @@rowcount>0
		insert #Account(Id,Name,UnderAccountId) 
		select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
		join #Account a2 on a1.UnderAccountID=a2.ID 
		left join #Account a3 on a1.ID=a3.ID
		where a3.ID is null
   
	
	if @SalesmanID>0
		delete a from #Account a join invCustomer c on a.ID=c.AccountID where c.SalesmanID<>@SalesmanID or c.SalesmanID is null
 
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
		delete t1 from #Account t1 
		left outer join @T1 t2 on t1.ID = t2.Id 
		where t2.Id is null
	  end
	end 


	--Active
	if @Status in (0,1)
	Begin
		if object_id('invCustomer') is not null
		Begin
			delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
		end
	End
	

  --Phone
  update a set a.Phone=isnull(nullif(c.Phone,''),c.MobileNo) from #Account a join invCustomer c on a.ID=c.AccountID

  
  /*Amount*/
  insert #Due(SNo,ID,Date,VTypeID,No,Description,Amount) 
  select row_number()over(order by Date,No)SNo, DebtorID,Date,d.VoucherTypeID,isnull(No,0),d.Description,sum(Amount) from aTransaction d 
  join #Account a on a.ID=d.DebtorID 
  where (CompanyID=@CompanyId or @CompanyId=0)
  and (date <= @ToDate or Date is null) 
  and (CostCentreId=@CostCentreId or @CostCentreId=0)
  group by DebtorID,PeriodID,date,d.VoucherTypeID,d.No,d.Description

  
  insert @FinalDue (ID,Date,SNo,RSales) 
  select d.ID,dd.date,dd.SNo,sum(d.Amount) from #Due d
  join (select date,SNo,ID from #Due)dd
  on d.ID = dd.ID and d.SNo <= dd.SNo
  group by d.ID,dd.SNo,dd.date

  --Receipts
  declare @aTransaction table(VoucherTypeID int,CNo varchar(50),DebtorId int,CreditorId int,AccountId int,Date int,CompanyId int,Amount float)
  insert @aTransaction
  select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
  from aTransaction d join #Account a on a.id=d.CreditorID 
  where (date <=@ToDate or Date is null) 
  and (CompanyId=@CompanyId or @CompanyId=0)
  and (CostCentreId=@CostCentreId or @CostCentreId=0)

  

	if @Type=3 --W/O PDC
	Begin
		declare @CQR int,@CQP int,@CQC int,@BR int,@BP int
		select @CQR=ChequeReceipt,@CQP=ChequePayment,@CQC=ChequeClearing,@BR=BillwiseReceipt,@BP=BillwisePayment from aVoucherTypeSettings
		delete @aTransaction where VoucherTypeID in(@CQR,@CQP,@BR,@BP) and CNo is not null

		insert @aTransaction
		select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
		from aTransaction d join #Account a on a.id=d.AccountID 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		declare @PDCP int,@PDCR int
		select @PDCP=PDCPayable,@PDCR=PDCReceivable from aAccountSettings 
	
		-- To delete bounced one
		delete @aTransaction where (DebtorID=@PDCP or DebtorID=@PDCR) and CreditorId=@AccountId
		delete @aTransaction where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID=@AccountId
		-----

		update @aTransaction set DebtorID=AccountID,AccountID=null where (DebtorID=@PDCP or DebtorID=@PDCR)
		update @aTransaction set CreditorID=AccountID,AccountID=null where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID<>AccountID
		
	End

  update r set r.totreceived = d.Amount from @FinalDue r join
  (select CreditorID,sum(Amount)Amount from @aTransaction group by CreditorID) d on d.CreditorID = r.ID

  delete from @FinalDue where round(RSales,1) <= round(isnull(TotReceived,0),1)

  delete d from #Due d left join @FinalDue f on d.ID=f.ID and d.SNo=f.SNo where f.SNo is null
  
  if not exists(select * from @FinalDue where RSales>isnull(TotReceived,0)) delete #Due

  update @FinalDue set Balance = RSales - isnull(TotReceived,0)

  declare @MinNo table(ID int,SNo int)
  insert @MinNo select ID,min(SNo) from @FinalDue group by ID

  delete d from #Due d join @MinNo m on d.ID = m.ID and d.SNo < m.SNo
  update d set d.Amount = f.balance from #Due d join @MinNo m on d.ID = m.ID and m.SNo = d.SNo join @FinalDue f on f.ID = m.ID and m.SNo = f.SNo
  ---------------

  --For calculating age, no future date need to consider
  if @ToDate>convert(varchar,current_timestamp,112) 
	  set @ToDate=convert(varchar,current_timestamp,112)


  --Filtering days
  if @From is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<@From 

  if @To is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))>@To
  ----
  
  
  declare @Line varchar(13)
  set @Line=REPLICATE('_',13)

  declare @AI int
  select @AI=AgeInterval from aOption
  
  declare @1C varchar(max)
  select @1C=cast(@AI+1 as varchar)+'-'+cast(2*@AI as varchar)

  declare @2C varchar(max)
  select @2C=cast(2*@AI+1 as varchar)+'-'+cast(3*@AI as varchar)

  declare @3C varchar(max)
  select @3C=cast(3*@AI+1 as varchar)+'-'+cast(4*@AI as varchar)

  declare @4C varchar(max)
  select @4C=cast(4*@AI+1 as varchar)+'-'
  
  declare @DecimalFormat int
  select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption	

  if @Type in(1,2,3)
  Begin	
	
	--Balance
	declare @DueBal table(Ord int,ID int,Date int null default 0,VtypeID int,No int,Description nvarchar(200),Amount money,Balance money)
	
	insert @DueBal
    select row_number() over (partition by ID order by ID,Date),ID,Date,VtypeID,No,Description,Amount,null from #Due
	
	
	;with b as
	(select b.Ord,b.id,sum(s.Amount) Balance from @DueBal b join @DueBal s on s.id=b.id and s.Ord<=b.Ord group by b.Ord,b.id)

	update s set s.Balance=b.Balance from @DueBal s join b on b.id=s.id and s.Ord=b.Ord
	---------------------
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)

	Begin
	 		
		create table #FBal(Ord int,ID int,LedgerAccount nvarchar(100),Date int,VtypeID int,No int,Description nvarchar(200),Amount varchar(50),Age varchar(25),Balance varchar(50),Name nvarchar(100),Days int)
		 
		insert #FBal(Ord,ID,Date,VtypeID,No,Description,Amount,Age,Balance)
		select Ord,ID,Date,VtypeID,No,Description,
		convert(varchar,cast(Amount as money),4),
		datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)),
		convert(varchar,cast(Balance as money),4) from @DueBal

		
		insert #FBal(Ord,ID,Amount,Balance)
		select max(Ord)+1,ID,@Line,@Line from @DueBal group by ID 

		insert #FBal(Ord,ID,Amount)
		select max(Ord)+2,ID,convert(varchar,cast(sum(Amount) as money),4) from @DueBal group by ID 

		declare @AL int
		select @AL=max(len(Name)) from #Account

		declare @DL int
		select @DL=max(len(Description)) from #FBal

		insert #FBal(LedgerAccount,Ord,ID,Description,Age,Amount,Balance)
		select REPLICATE('_',@AL),max(Ord)+3,ID,REPLICATE('_',@DL),REPLICATE('_',5),@Line,@Line from @DueBal group by ID 

		declare @Address table(ID int,Address nvarchar(100),Ord int)
		insert @Address select ID,c.Name,1 from invCustomer c join #Account a on c.AccountID=a.ID
		insert @Address select ID,c.Address1,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address1)>0 group by ID,c.Address1 
		insert @Address select ID,c.Address2,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address2)>0 group by ID,c.Address2 
		insert @Address select ID,c.Address3,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address3)>0 group by ID,c.Address3 
		insert @Address select ID,c.Place,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Place)>0 group by ID,c.Place
		insert @Address select ID,c.Phone,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Phone)>0 group by ID,c.Phone
		insert @Address select ID,c.MobileNo,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.MobileNo)>0 group by ID,c.MobileNo

		update f set f.LedgerAccount=c.Address from #FBal f join @Address c on f.ID=c.ID and f.Ord=c.Ord where LedgerAccount is null
		
		-- Just for Ordering by Name
		update f set f.Name=a.Name from #Account a join #FBal f on f.ID=a.ID
		
		if @Type in(1,3)
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,Age,Amount,Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
		else
		Begin
			update #FBal set Days=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))
			exec('
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,Amount,
			case when Days <='+@AI+' then Amount end[ 0-'+@AI+'] ,
			case when Days between '+@AI+'+1 and 2*'+@AI+' then Amount end[ '+@1C+'],
			case when Days between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end[ '+@2C+'],
			case when Days between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end[ '+@3C+'],
			case when Days >4*'+@AI+' or Date is null then Amount end[ '+@4C+'],
			Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
			')
		End
	End
	Else
	Begin
		if @Type in(1,3)
		Begin
			select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,convert(varchar,cast(d.Amount as money),@DecimalFormat) Amount,datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))Age,convert(varchar,cast(d.Balance as money),@DecimalFormat)Balance from @DueBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			union all
			select null,null,null,null,null,@Line,null,@Line
			union all
			select null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat),null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat) from @DueBal
			union all
			select null,null,null,null,null,@Line,null,@Line
		End
		Else
		Begin	
			;with a as
			(select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,
			 d.Amount Amount,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<31 then Amount end [ 0-30] ,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 31 and 45 then Amount end [ 31-45],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 46 and 60 then Amount end [ 46-60],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 61 and 90 then Amount end [ 61-90],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) > 90 or Date is null then Amount end [ 90-],
			 d.Balance from @DueBal d 
			 left join aVoucherType v on d.VTypeID=v.ID
			 )

			 select Date,VoucherTypeID,VType,No,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-],convert(varchar,Balance,@DecimalFormat)Balance from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 union all
			 select null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat),convert(varchar,sum([ 0-30]),@DecimalFormat),convert(varchar,sum([ 31-45]),@DecimalFormat),convert(varchar,sum([ 46-60]),@DecimalFormat),convert(varchar,sum([ 61-90]),@DecimalFormat),convert(varchar,sum([ 90-]),@DecimalFormat),null from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 
		End
	End
  End
  Else
  Begin
	  update #Due set Date=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))--,Amount=convert(varchar,Amount,@DecimalFormat)
	  
	  exec
	  ('
	  ;with a as	
	  (select a.Name Account,a.Phone,d.* from 
	  (select ID,
	  sum(case when Date <='+@AI+' then Amount end)[ 0-'+@AI+'] ,
	  sum(case when Date between '+@AI+'+1 and 2*'+@AI+' then Amount end)[ '+@1C+'],
	  sum(case when Date between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end)[ '+@2C+'],
	  sum(case when Date between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end)[ '+@3C+'],
	  sum(case when Date >4*'+@AI+' or Date is null then Amount end)[ '+@4C+'],
	  sum(Amount)Total
	  from #Due group by ID)d
	  join #Account a on a.ID = d.ID)

	  select ID,Account,Phone,convert(varchar,[ 0-'+@AI+'],'+@DecimalFormat+')[ 0-'+@AI+'],convert(varchar,[ '+@1C+'],'+@DecimalFormat+')[ '+@1C+'],convert(varchar,[ '+@2C+'],'+@DecimalFormat+')[ '+@2C+'],convert(varchar,[ '+@3C+'],'+@DecimalFormat+')[ '+@3C+'],convert(varchar,[ '+@4C+'],'+@DecimalFormat+')[ '+@4C+'],convert(varchar,Total,'+@DecimalFormat+')Total from a
	  union all
	  select null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  union all
	  select null,null,null,convert(varchar,sum([ 0-'+@AI+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@1C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@2C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@3C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@4C+']),'+@DecimalFormat+'),convert(varchar,sum(Total),'+@DecimalFormat+') from a
	  union all
	  select null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  ')
  End  

  GO


  if not exists(select 1 from syscolumns where name='SalesmanID' and id=object_id('aBillwiseReceiptHdr'))
	alter table aBillwiseReceiptHdr add SalesmanID int foreign key references invSalesman(ID)

go

if OBJECT_ID('spSaveBillwiseReceipt') is not null drop proc spSaveBillwiseReceipt

go

create proc spSaveBillwiseReceipt
@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@CustomerID int,
@Amount float,
@Advance float,
@ChequeNo varchar(25),
@ChequeDate int=null,
@Description nvarchar(100),
@CostCentreId int=null,
@SalesmanId int=null,
@xml xml,
@CompanyID int,
@PeriodID int,
@PaymentType int=0
as

set nocount on
set xact_abort on

Begin Transaction

set @CustomerID=isnull(@CustomerID,0)

--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aBillwiseReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID

	insert aBillwiseReceiptHdr([No],RefNo,Date,DebtorID,CustomerID,Amount,Advance,Description,CostCentreId,CompanyID,PeriodID,PaymentType,SalesmanID)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@CustomerID,nullif(@Amount,0),nullif(@Advance,0),nullif(@Description,''),@CostCentreId,@CompanyID,@PeriodID,@PaymentType,@SalesmanID)
End
else
	update aBillwiseReceiptHdr set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,CustomerID=@CustomerID,Amount=nullif(@Amount,0),Advance=nullif(@Advance,0),CostCentreId=@CostCentreId,Description=@Description,PaymentType=@PaymentType,SalesmanID=@SalesmanID
	where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aBillwiseReceiptDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @Dtl table(EPeriodID int,EVoucherTypeID int,ENo int,ESNo int,Amount float,Paid float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @Dtl(EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount)
select nullif(EPeriodID,0),nullif(EVoucherTypeID,0),nullif(ENo,0),nullif(ESNo,0),Amount,nullif(Paid,0),nullif(Discount,0) from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
EPeriodID int '@PeriodID',
EVoucherTypeID int '@VoucherTypeID',
ENo int '@No',
ESNo int '@SNo',
Amount float '@Amount',
Paid float '@Paid',
Discount float '@Discount'
) 
where Paid<>0 or Discount<>0

exec sp_xml_removedocument @idoc

insert aBillwiseReceiptDtl(No,EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount,CompanyID,PeriodID)
select @No,EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount,@CompanyID,@PeriodID from @Dtl


--Posting
declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

if @PaymentType=1
Begin
	declare @PDCReceivable int
	if len(rtrim(@ChequeNo))>0
	Begin
		select @PDCReceivable=PDCReceivable from aAccountSettings where CompanyID=@CompanyID
		insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CNo,CDate,AccountID,CostCentreId)
		values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@PDCReceivable,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@ChequeNo,@ChequeDate,@DebtorID,@CostCentreId)
	End
	Else
		insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreId,CDate)
		values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorId,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@CostCentreId,@ChequeDate)
		
End
else if @PaymentType=2
Begin
	--declare @CreditCard int
	--select @CreditCard=CreditCard from aAccountSettings where CompanyID=@CompanyID
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CNo,CostCentreId)
	values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorID,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@ChequeNo,@CostCentreId)
End
Else
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreId)
	values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorID,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@CostCentreId)


--Discount
declare @DiscountPaid int
select @DiscountPaid=DiscountPaid from aAccountSettings where CompanyID=@CompanyID

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,RefNo,CostCentreId)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DiscountPaid,@CustomerID,sum(Discount),@RefNo,@CostCentreId from @Dtl having sum(Discount)<>0


Commit
	
select @No 



go

if object_id('spGetBillwiseReceipt') is not null drop proc spGetBillwiseReceipt

go

create proc spGetBillwiseReceipt
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.DebtorID,a.Name Debtor,fh.CustomerID,c.Name Customer,fh.Amount,fh.Advance,ch.CNo ChequeNo,ch.CDate ChequeDate,fh.Description,fh.CostCentreId,fh.PaymentType,fh.SalesmanId from aBillwiseReceiptHdr fh
join aAccount a on fh.DebtorID=a.ID
join aAccount c on fh.CustomerID=c.ID
join aTransaction ch on fh.CompanyID=ch.CompanyID and fh.PeriodID=ch.PeriodID and fh.No=ch.No
join aVoucherTypeSettings v on ch.VoucherTypeID=v.BillwiseReceipt
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
	exec spGetCustomerOutstandingBills @No=@No,@CompanyID=@CompanyID,@PeriodID=@PeriodID

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
	select row_number() over (order by Date,VoucherTypeId desc,No,SNo),*,null from @Ledger

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
		select PeriodID,Date,Company,CostCentre,VoucherTypeID,VType,No,RefNo,Account,IAccount,Description,convert(varchar,cast(Debit as money),@DecimalFormat)Debit,convert(varchar,cast(Credit as money),@DecimalFormat)Credit,convert(varchar,cast(SR as money),@DecimalFormat)SR,convert(varchar,cast(Discount as money),@DecimalFormat)Discount,convert(varchar,cast(Balance as money),@DecimalFormat)Balance from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
		union all
		select null,null,null,null,null,null,null,null,null,null,null,convert(varchar,cast(sum(Debit) as money),@DecimalFormat),convert(varchar,cast(sum(Credit) as money),@DecimalFormat),convert(varchar,cast(sum(SR) as money),@DecimalFormat),convert(varchar,cast(sum(Discount) as money),@DecimalFormat),convert(varchar,@BS*cast(isnull(sum(Debit),0)-isnull(sum(Credit),0)-isnull(sum(SR),0)-isnull(sum(Discount),0) as money),@DecimalFormat) from #LB
		union all
		select null,null,null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line
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

if OBJECT_ID('spSaveBankReceipt') is not null drop proc spSaveBankReceipt

go

create proc spSaveBankReceipt

@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@RepID int=null,
@Total float,
@xml xml,

@CompanyID int,
@PeriodID int,
@UserID int
as

set nocount on


--Duplicate RefNo
declare @Message varchar(100)
select @Message='This Ref.No already given for the Entry No. ' + cast(No as varchar) from aBankReceiptHdr where RefNo=@RefNo and No<>@No and CompanyID=@CompanyID and PeriodID=@PeriodID and Total is not null

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
	select @No=isnull(max(No),0)+1 from aBankReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aBankReceiptHdr([No],RefNo,Date,DebtorID,RepID,Total,CompanyID,PeriodID,UserID)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@RepID,@Total,@CompanyID,@PeriodID,@UserID)
End
else
	update aBankReceiptHdr set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,RepID=@RepID,Total=@Total,UserID=@UserID where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aBankReceiptDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @BankReceiptDtl table(SNo int,CreditorID int,CostCentreID int,Description nvarchar(100),Amount float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @BankReceiptDtl(SNo,CreditorID,CostCentreID,Description,Amount,Discount)
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

insert aBankReceiptDtl(No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,CompanyID,PeriodID)
select @No,SNo,CreditorID,CostCentreID,Description,Amount,Discount,@CompanyID,@PeriodID from @BankReceiptDtl
 


--Posting
declare @VoucherTypeID int
select @VoucherTypeID=isnull(BankReceipt,0) from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

--Amount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,@DebtorID,CreditorID,Amount,isnull(Description,'Bank  Transaction'),@RefNo,CostCentreID from @BankReceiptDtl where Amount<>0

--Discount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,10000+SNo,a.DiscountPaid,CreditorID,Discount,isnull(Description,'Discount'),@RefNo,CostCentreID from @BankReceiptDtl c,aAccountSettings a where c.Discount<>0 and a.CompanyID=@CompanyID

Commit
	
select @No No,@Message Message



go

if OBJECT_ID('spSaveBankPayment') is not null drop proc spSaveBankPayment

go

create proc spSaveBankPayment

@No int,
@RefNo nvarchar(50),
@Date int,
@CreditorID int,
@Total float,
@xml xml,
@CompanyID int,
@PeriodID int,
@UserID int
as

set nocount on


--Duplicate RefNo
declare @Message varchar(100)
select @Message='This Ref.No already given for the Entry No. ' + cast(No as varchar) from aBankPaymentHdr where RefNo=@RefNo and No<>@No and CompanyID=@CompanyID and PeriodID=@PeriodID and Total is not null

if @Message is not null
Begin
	select @No No,@Message Message
	return
End

set xact_abort on
Begin Transaction

set @CreditorID=isnull(@CreditorID,0)
	
--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aBankPaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID
	insert aBankPaymentHdr([No],RefNo,Date,CreditorID,Total,CompanyID,PeriodID,UserID)
	values(@No,nullif(@RefNo,''),@Date,@CreditorID,@Total,@CompanyID,@PeriodID,@UserID)
End
else
	update aBankPaymentHdr set RefNo=nullif(@RefNo,''),Date=@Date,CreditorID=@CreditorID,Total=@Total,UserID=@UserID where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aBankPaymentDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @BankPaymentDtl table(SNo int,DebtorID int,CostCentreID int,Description nvarchar(200),Amount float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @BankPaymentDtl(SNo,DebtorID,CostCentreID,Description,Amount,Discount)
select SNo,DebtorID,nullif(CostCentreID,0),nullif(Description,''),Amount,nullif(Discount,0) from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
SNo int '@KSNo',
DebtorID int '@DebtorID',
CostCentreID int '@CostCentreID',
Description nvarchar(200) '@Description',
Amount float '@Amount',
Discount float '@Discount'
) 
where DebtorID>0
exec sp_xml_removedocument @idoc

insert aBankPaymentDtl(No,SNo,DebtorID,CostCentreID,Description,Amount,Discount,CompanyID,PeriodID)
select @No,SNo,DebtorID,CostCentreID,Description,Amount,Discount,@CompanyID,@PeriodID from @BankPaymentDtl

--Posting
declare @VoucherTypeID int
select @VoucherTypeID=isnull(BankPayment,0) from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,DebtorID,@CreditorID,Amount,isnull(Description,'Bank Payment'),@RefNo,CostCentreID from @BankPaymentDtl

--Discount
insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,SNo,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreID)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,SNo,DebtorID,a.DiscountReceived,Discount,Description,@RefNo,CostCentreID 
from @BankPaymentDtl c,aAccountSettings a where c.Discount<>0 and a.CompanyID=@CompanyID

Commit
	
select @No No,@Message Message



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
		insert invOption(ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,CompanyID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,CompanyTransferCompanyFromId,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces)
		select top 1 ItemCodeLength,DockContent,TaxOption,TransferDb,AccountLinking,InPutTaxAccount,OutPutTaxAccount,DefaultCustomer,AdditionCaption,AdditionAccount,SalesPrintType,SalesEntryFocus,PurchaseEntryFocus,PurchaseReturnEntryFocus,SalesReturnEntryFocus,DefaultSearchInPurchase,DefaultSearchInPurchaseReturn,DefaultSearchInSales,DefaultSearchInSalesReturn,DefaultSearchOfVendor,DefaultSearchOfCustomer,DefaultFocusOfPurchase,DefaultFocusOfPurchaseReturn,DefaultFocusOfSales,DefaultFocusOfSalesReturn,DefaultFocusControlOfPurchase,DefaultFocusControlOfPurchaseReturn,DefaultFocusControlOfSales,DefaultFocusControlOfSalesReturn,SkipToNextRowPurchase,SkipToNextRowPurchaseReturn,SkipToNextRowSales,SkipToNextRowSalesReturn,CheckOutOfStock,BlockNonStockEntry,SalesFooterFocus,CustomerSalesDetails,PurchaseRate,RoundOffInSales,DuplicateCustomer,SalesRoundOffAccount,SalesRate,Password,DefaultBaseUomId,CompelsorySalesRateEntry,AutoProductCode,ProductPrefix,BatchAndExpiry,NonTaxableId,RoundOffInPurchase,PurchaseRoundOffAccount,DefaultReportDate,DecimalFormat,PaymentModeInPurchase,PaymentModeInSales,@ID,DefaultWareHouseID,GrossEditableInPurchase,ExpensesInPurchase,SalesFooterAddition,DefaultVendor,ProductionAccount,SalesAdditionAccount,PRateCalculation,DefaultPurchaseSearchType,DefaultSalesSearchType,SalesPrePrintingCaption,SalesFromAndToTimes,RentalAccount,CreditNote,SalesPrePrintingMessage,StockCalculation,JobWorksToNotesInSales,Approval,PurchaseDisplayStock,SalesBlockByCreditLimit,AddMaterialsInJobInvoicePrint,AddLabourCostToJobInvoice,SalesRateSelection,RemoteServerName,RemoteUserName,RemoteUserPassword,RemoteDBO,AutoExportingInterval,SalesIndividualExporting,PurchaseIndividualExporting,CompanyTransferAccountID,VendorUnder,CustomerUnder,BarcodePrefix,ProductCompulsoryInQt,MaterialSpecificationInQT,ProductionAutoCostCalculation,CategoryPropertyID,SalesDP,ExportingProfitPercent,SalesNRateEdit,SalesRoundOffCaption,ForeignCurrencyInPurchase,SalestoVendors,CustomerSelectionInJobForm,ReportColumnWidth,InterChangeRateQty,SRCustomerItemsOnly,EditableAutoCode,AllowDuplicateProduct,ShowSnoFromPurchase,ShowSnoFromSales,UsePropertyCodeAsPrefix,Property1Id,Property2Id,Property1Length,Property2Length,RetrieveProdcutDetails,SalesCalculateFooterAddition,PurchaseInvoiceNoMandatory,QoutationMultipleImporting,SRAccount,SalesDisplayStock,SalesPostPaidSeparately,SalesInvoiceNoMandatory,SalesSalesmanMandatory,ProductAutoEntry,SalesFontBold,JobTaxOption,SalesKeepLastDate,SalesPrintFile,ShowSalesAnalysis,ProductDisplayCP,ProductDisplayStock,SalesDisplayCP,SalesQuantityRate,SalesDisplayProfit,SalesBlockBelowCost,ReportPrintAlignment,PurchaseToCustomers,ProductClearProperty,SalesAllowCreditDefaultCustomer,ExcessShortageAccountID,SalesAllowDuplicateInvoiceNo,SalesPromptOldDayEdit,SalesBlockBelowWRate,SalesGenerateCodeInRemarks,SalesFooterPage,LPOPrintFile,MessageForUniqueBarcode,SalesPrintFile1,SalesEditableGross,SalesDisplayProductDetails,SalesStyle,AutoSynchronizingInterval,SalesDetailedDescription,CompanyTransferApproval,SalesMessage1,ProfitCalculation,CompanyTransferRate,UploadReceiptAndPayment,PurchaseSRateNonEditable,CheckSalesDueDate,ProductMixingCaption,ProductionMemorize,SalesApproval,ShowPurchaseProprtyFromProduct,NextBarcode,ExpiryAlertDays,WareHouseTransferAccountId,PurchaseCPCalculation,InterCompanySerialNo,WareHouseTransferCrossChecking,@Id,PurchaseNetTotalVerification,RentalAlertDays,QtyDecimalPlaces from invOption
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
	insert aAccountSettings(CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,CompanyID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity)
	select top 1 CashInHand,Sales,Purchase,DiscountPaid,DiscountReceived,Vendors,Customers,CreditCard,Employees,ForeignCurrency,@ID,PDCPayable,PDCReceivable,InputTax,OutputTax,Profit,Adjustment,Commission,StockInHand,OpeningBalanceEquity from aAccountSettings


if not exists(select 1 from invProjectSettings where CompanyID=@ID)
	insert invProjectSettings(PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,CompanyId)
	select top 1 PointSettingsOfProduct,Rep1InSales,Rep1Caption,Rep2InSales,Rep2Caption,AdditionInSales,DataTransfer,SizePropertyId,PurchaseProperty,AutoBarcode,SalesProperty,PiecesInSales,PiecesCaption,AirwayBillNoInSales,AirwayBillNoCaption,Mailing,ProductSerialNo,SalesRateInPurchase,HideQtyInPrint,RcvDealer,ClearSales,GarageWorks,Water,PDADevice,PrintWithoutSaving,Transportation,DayEnd,UniversalNoSeries,@ID from invProjectSettings


select 0 status ,'Saved Successfully' Message

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

declare @Transaction table(Date int,VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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


--Cash
insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name
having sum(case when c.CD=0 then Amount end) is not null


--Billwise Receipt
declare @VtypeId int
select @VtypeId=BillwiseReceipt from aVoucherTypeSettings

insert @Transaction
select Date,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@VtypeId,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@VtypeId
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name




if (@SalesmanId>0)
	delete @Transaction where isnull(SalesmanId,0)<>@SalesmanId


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption

;with f as
(select null Ord,cast(cast(Date as varchar) as smalldatetime)Date,VType, No,Customer,SalesMan,Account,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,t.Discount,@DecimalFormat)Discount,convert(varchar,isnull(t.Amount,0)+isnull(t.Discount,0),@DecimalFormat)Total,VoucherTypeID,PeriodID from @Transaction t 
union all
select 1,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
union all
select 2,null,null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat)Amount,convert(varchar,cast(sum(Discount) as money),@DecimalFormat)Discount,convert(varchar,cast(sum(isnull(Amount,0)+isnull(Discount,0)) as money),@DecimalFormat),null,null from @Transaction
union all
select 3,null,null,null,null,null,null,null,@Line,@Line,@Line,null,null
)

select Date,VType,No,Customer,SalesMan,Account,Description,Amount,Discount,Total,VoucherTypeID,PeriodID from f order by Ord,Date,No


go


if object_id('spCustomersAgeing') is not null drop proc spCustomersAgeing

go

create proc spCustomersAgeing 
@CompanyId int=1,
@ToDate int,
@AccountID int=0,
@Type tinyint, --0 Summary,1 Detailed
@From int=null,
@To int=null,
@SalesmanID int=null,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null,
@CostCentreId int=0

as

  set nocount on
  set transaction isolation level read uncommitted

  create table #Due 
  (SNo int,
   ID numeric ,
   Date int null default 0,
   VtypeID int,
   No int,
   Description nvarchar(200),
   Amount money
  )

  declare @FinalDue table
  (ID numeric ,
   Date int null default 0,
   SNo int,
   Rsales float ,
   TotReceived float ,
   Balance float )


   create table #Account (ID int,Name nvarchar(100),UnderAccountID int,Phone varchar(100))
   insert #Account(Id,Name,UnderAccountId) 
   select a.ID,a.name,a.ID from aAccount a join aSubGroupSettings sg on a.AccountSubGroupID=sg.SundryDebtors where	a.ID=@AccountID

   --Drilling for Under Accounts,
	--while @Type in(1,2) and @@rowcount>0
		insert #Account(Id,Name,UnderAccountId) 
		select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
		join #Account a2 on a1.UnderAccountID=a2.ID 
		left join #Account a3 on a1.ID=a3.ID
		where a3.ID is null
   
	
	if @SalesmanID>0
		delete a from #Account a join invCustomer c on a.ID=c.AccountID where c.SalesmanID<>@SalesmanID or c.SalesmanID is null
 
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
		delete t1 from #Account t1 
		left outer join @T1 t2 on t1.ID = t2.Id 
		where t2.Id is null
	  end
	end 


	--Active
	if @Status in (0,1)
	Begin
		if object_id('invCustomer') is not null
		Begin
			delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
		end
	End
	

  --Phone
  update a set a.Phone=isnull(nullif(c.Phone,''),c.MobileNo) from #Account a join invCustomer c on a.ID=c.AccountID

  
  /*Amount*/
  insert #Due(SNo,ID,Date,VTypeID,No,Description,Amount) 
  select row_number()over(order by Date,No)SNo, DebtorID,Date,d.VoucherTypeID,isnull(No,0),d.Description,sum(Amount) from aTransaction d 
  join #Account a on a.ID=d.DebtorID 
  where (CompanyID=@CompanyId or @CompanyId=0)
  and (date <= @ToDate or Date is null) 
  and (CostCentreId=@CostCentreId or @CostCentreId=0)
  group by DebtorID,PeriodID,date,d.VoucherTypeID,d.No,d.Description

  
  insert @FinalDue (ID,Date,SNo,RSales) 
  select d.ID,dd.date,dd.SNo,sum(d.Amount) from #Due d
  join (select date,SNo,ID from #Due)dd
  on d.ID = dd.ID and d.SNo <= dd.SNo
  group by d.ID,dd.SNo,dd.date

  --Receipts
  declare @aTransaction table(VoucherTypeID int,CNo varchar(50),DebtorId int,CreditorId int,AccountId int,Date int,CompanyId int,Amount float)
  insert @aTransaction
  select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
  from aTransaction d join #Account a on a.id=d.CreditorID 
  where (date <=@ToDate or Date is null) 
  and (CompanyId=@CompanyId or @CompanyId=0)
  and (CostCentreId=@CostCentreId or @CostCentreId=0)

  

	if @Type=3 --W/O PDC
	Begin
		declare @CQR int,@CQP int,@CQC int,@BR int,@BP int
		select @CQR=ChequeReceipt,@CQP=ChequePayment,@CQC=ChequeClearing,@BR=BillwiseReceipt,@BP=BillwisePayment from aVoucherTypeSettings
		delete @aTransaction where VoucherTypeID in(@CQR,@CQP,@BR,@BP) and CNo is not null

		insert @aTransaction
		select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
		from aTransaction d join #Account a on a.id=d.AccountID 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		declare @PDCP int,@PDCR int
		select @PDCP=PDCPayable,@PDCR=PDCReceivable from aAccountSettings 
	
		-- To delete bounced one
		delete @aTransaction where (DebtorID=@PDCP or DebtorID=@PDCR) and CreditorId=@AccountId
		delete @aTransaction where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID=@AccountId
		-----

		update @aTransaction set DebtorID=AccountID,AccountID=null where (DebtorID=@PDCP or DebtorID=@PDCR)
		update @aTransaction set CreditorID=AccountID,AccountID=null where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID<>AccountID
		
	End

  update r set r.totreceived = d.Amount from @FinalDue r join
  (select CreditorID,sum(Amount)Amount from @aTransaction group by CreditorID) d on d.CreditorID = r.ID

  delete from @FinalDue where round(RSales,1) <= round(isnull(TotReceived,0),1)

  delete d from #Due d left join @FinalDue f on d.ID=f.ID and d.SNo=f.SNo where f.SNo is null
  
  if not exists(select * from @FinalDue where RSales>isnull(TotReceived,0)) delete #Due

  update @FinalDue set Balance = RSales - isnull(TotReceived,0)

  declare @MinNo table(ID int,SNo int)
  insert @MinNo select ID,min(SNo) from @FinalDue group by ID

  delete d from #Due d join @MinNo m on d.ID = m.ID and d.SNo < m.SNo
  update d set d.Amount = f.balance from #Due d join @MinNo m on d.ID = m.ID and m.SNo = d.SNo join @FinalDue f on f.ID = m.ID and m.SNo = f.SNo
  ---------------

  --For calculating age, no future date need to consider
  if @ToDate>convert(varchar,current_timestamp,112) 
	  set @ToDate=convert(varchar,current_timestamp,112)


  --Filtering days
  if @From is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<@From 

  if @To is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))>@To
  ----
  
  
  declare @Line varchar(13)
  set @Line=REPLICATE('_',13)

  declare @AI int
  select @AI=AgeInterval from aOption
  
  declare @1C varchar(max)
  select @1C=cast(@AI+1 as varchar)+'-'+cast(2*@AI as varchar)

  declare @2C varchar(max)
  select @2C=cast(2*@AI+1 as varchar)+'-'+cast(3*@AI as varchar)

  declare @3C varchar(max)
  select @3C=cast(3*@AI+1 as varchar)+'-'+cast(4*@AI as varchar)

  declare @4C varchar(max)
  select @4C=cast(4*@AI+1 as varchar)+'-'
  
  declare @DecimalFormat int
  select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption	

  if @Type in(1,2,3)
  Begin	
	
	--Balance
	declare @DueBal table(Ord int,ID int,Date int null default 0,VtypeID int,No int,Description nvarchar(200),Amount money,Balance money)
	
	insert @DueBal
    select row_number() over (partition by ID order by ID,Date),ID,Date,VtypeID,No,Description,Amount,null from #Due
	
	
	;with b as
	(select b.Ord,b.id,sum(s.Amount) Balance from @DueBal b join @DueBal s on s.id=b.id and s.Ord<=b.Ord group by b.Ord,b.id)

	update s set s.Balance=b.Balance from @DueBal s join b on b.id=s.id and s.Ord=b.Ord
	---------------------
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)

	Begin
	 		
		create table #FBal(Ord int,ID int,LedgerAccount nvarchar(100),Date int,VtypeID int,No int,Description nvarchar(200),Amount varchar(50),Age varchar(25),Balance varchar(50),Name nvarchar(100),Days int)
		 
		insert #FBal(Ord,ID,Date,VtypeID,No,Description,Amount,Age,Balance)
		select Ord,ID,Date,VtypeID,No,Description,
		convert(varchar,cast(Amount as money),4),
		datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)),
		convert(varchar,cast(Balance as money),4) from @DueBal

		
		insert #FBal(Ord,ID,Amount,Balance)
		select max(Ord)+1,ID,@Line,@Line from @DueBal group by ID 

		insert #FBal(Ord,ID,Amount)
		select max(Ord)+2,ID,convert(varchar,cast(sum(Amount) as money),4) from @DueBal group by ID 

		declare @AL int
		select @AL=max(len(Name)) from #Account

		declare @DL int
		select @DL=max(len(Description)) from #FBal

		insert #FBal(LedgerAccount,Ord,ID,Description,Age,Amount,Balance)
		select REPLICATE('_',@AL),max(Ord)+3,ID,REPLICATE('_',@DL),REPLICATE('_',5),@Line,@Line from @DueBal group by ID 

		declare @Address table(ID int,Address nvarchar(100),Ord int)
		insert @Address select ID,c.Name,1 from invCustomer c join #Account a on c.AccountID=a.ID
		insert @Address select ID,c.Address1,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address1)>0 group by ID,c.Address1 
		insert @Address select ID,c.Address2,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address2)>0 group by ID,c.Address2 
		insert @Address select ID,c.Address3,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address3)>0 group by ID,c.Address3 
		insert @Address select ID,c.Place,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Place)>0 group by ID,c.Place
		insert @Address select ID,c.Phone,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Phone)>0 group by ID,c.Phone
		insert @Address select ID,c.MobileNo,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.MobileNo)>0 group by ID,c.MobileNo

		update f set f.LedgerAccount=c.Address from #FBal f join @Address c on f.ID=c.ID and f.Ord=c.Ord where LedgerAccount is null
		
		-- Just for Ordering by Name
		update f set f.Name=a.Name from #Account a join #FBal f on f.ID=a.ID
		
		if @Type in(1,3)
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,Age,Amount,Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
		else
		Begin
			update #FBal set Days=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))
			exec('
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,Amount,
			case when Days <='+@AI+' then Amount end[ 0-'+@AI+'] ,
			case when Days between '+@AI+'+1 and 2*'+@AI+' then Amount end[ '+@1C+'],
			case when Days between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end[ '+@2C+'],
			case when Days between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end[ '+@3C+'],
			case when Days >4*'+@AI+' or Date is null then Amount end[ '+@4C+'],
			Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
			')
		End
	End
	Else
	Begin
		if @Type in(1,3)
		Begin
			select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,convert(varchar,cast(d.Amount as money),@DecimalFormat) Amount,datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))Age,convert(varchar,cast(d.Balance as money),@DecimalFormat)Balance from @DueBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			union all
			select null,null,null,null,null,@Line,null,@Line
			union all
			select null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat),null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat) from @DueBal
			union all
			select null,null,null,null,null,@Line,null,@Line
		End
		Else
		Begin	
			;with a as
			(select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,
			 d.Amount Amount,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<31 then Amount end [ 0-30] ,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 31 and 45 then Amount end [ 31-45],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 46 and 60 then Amount end [ 46-60],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 61 and 90 then Amount end [ 61-90],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) > 90 or Date is null then Amount end [ 90-],
			 d.Balance from @DueBal d 
			 left join aVoucherType v on d.VTypeID=v.ID
			 )

			 select Date,VoucherTypeID,VType,No,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-],convert(varchar,Balance,@DecimalFormat)Balance from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 union all
			 select null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat),convert(varchar,sum([ 0-30]),@DecimalFormat),convert(varchar,sum([ 31-45]),@DecimalFormat),convert(varchar,sum([ 46-60]),@DecimalFormat),convert(varchar,sum([ 61-90]),@DecimalFormat),convert(varchar,sum([ 90-]),@DecimalFormat),null from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 
		End
	End
  End
  Else
  Begin
	  update #Due set Date=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))--,Amount=convert(varchar,Amount,@DecimalFormat)
	  
	  exec
	  ('
	  ;with a as	
	  (select a.Name Account,a.Phone,d.* from 
	  (select ID,
	  sum(case when Date <='+@AI+' then Amount end)[ 0-'+@AI+'] ,
	  sum(case when Date between '+@AI+'+1 and 2*'+@AI+' then Amount end)[ '+@1C+'],
	  sum(case when Date between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end)[ '+@2C+'],
	  sum(case when Date between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end)[ '+@3C+'],
	  sum(case when Date >4*'+@AI+' or Date is null then Amount end)[ '+@4C+'],
	  sum(Amount)Total
	  from #Due group by ID)d
	  join #Account a on a.ID = d.ID)

	  select * from
	  (select null Ord,ID,Account,Phone,convert(varchar,[ 0-'+@AI+'],'+@DecimalFormat+')[ 0-'+@AI+'],convert(varchar,[ '+@1C+'],'+@DecimalFormat+')[ '+@1C+'],convert(varchar,[ '+@2C+'],'+@DecimalFormat+')[ '+@2C+'],convert(varchar,[ '+@3C+'],'+@DecimalFormat+')[ '+@3C+'],convert(varchar,[ '+@4C+'],'+@DecimalFormat+')[ '+@4C+'],convert(varchar,Total,'+@DecimalFormat+')Total from a
	  union all
	  select 1,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  union all
	  select 2,null,null,null,convert(varchar,sum([ 0-'+@AI+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@1C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@2C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@3C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@4C+']),'+@DecimalFormat+'),convert(varchar,sum(Total),'+@DecimalFormat+') from a
	  union all
	  select 3,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  )b order by Ord,Account')
  End  

  GO


  if object_id('spGetChequeClearing') is not null drop proc spGetChequeClearing

go

create proc spGetChequeClearing
@No int=null,
@CompanyID int,
@PeriodID int
as

select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime)Date,fh.Bounce,fh.CostCentreId from aChequeClearingHdr fh
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

--Details
if @No is not null
	select cast(1 as bit)CHE,Type,cd.EPeriodID,cd.EVTypeID,v.Name VType,cd.ENo,cast(cast(t.Date as varchar)as smalldatetime)Date,t.CNo,cast(cast(t.CDate as varchar)as smalldatetime)CDate,t.AccountID BankID,b.Name Bank,a.ID AccountID,a.Name Account,t.Description,t.Amount,cd.Commission 
	from aChequeClearingDtl cd 
	join aVoucherType v on cd.EVTypeID=v.ID
	join aTransaction t on cd.CompanyID=t.CompanyID and cd.EPeriodID=t.PeriodID and cd.EVtypeID=t.VoucherTypeID and cd.ENo=t.No
	join aAccount b on t.AccountID=b.ID
	cross join aVoucherTypeSettings vs
	join aAccount a on case when vs.ChequeReceipt=cd.EVtypeID or vs.BillwiseReceipt=cd.EVtypeID then t.CreditorID else t.DebtorID end=a.ID
	where cd.CompanyID=@CompanyID and cd.PeriodID=@PeriodID and  cd.No=@No

go

if exists(select * from sysIndexes where name='IndaJournalDtl') drop Index aJournalDtl.IndaJournalDtl
go
Create unique clustered Index IndaJournalDtl on aJournalDtl(CompanyId,PeriodId,No,AccountId,SNo) with fillfactor=90

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

declare @Transaction table(Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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

declare @VtypeId int
select @VtypeId=BillwiseReceipt from aVoucherTypeSettings

--Cash
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and t.VoucherTypeID<>@VtypeId
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null


--Billwise Receipt


insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@VtypeId,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@VtypeId
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name




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


if object_id('spGetJournal') is not null drop proc spGetJournal

go

create proc spGetJournal
@No int=null,
@CompanyID int,
@PeriodID int
as

declare @Header table(No int,RefNo varchar(50),Date smalldatetime,DrCr bit,AccountID int,Account nvarchar(100),Total float,TaxP float)

insert @Header(No,RefNo,Date,DrCr,AccountID,Account,Total)
select fh.No,fh.RefNo,cast(cast(fh.Date as varchar) as smalldatetime),fh.DrCr,fh.AccountID,a.Name Account,fh.Total from aJournalHdr fh
join aAccount a on fh.AccountID=a.ID
where fh.CompanyID=@CompanyID and fh.PeriodID=@PeriodID and (fh.No=@No or @No is null)
order by fh.No

update h set h.TaxP=t.Rate from @Header h join aAccount a on h.AccountID=a.Id join aTaxGroup t on a.TaxGroupID=t.ID

select * from @Header

--Details
if @No is not null
Begin
	declare @Details table(No int,SNo int,KSNo int,AccountID int,Account nvarchar(100),CostCentreID int,CostCentre nvarchar(100),Description nvarchar(100),Amount float,Taxp float,Tax float)

	insert @Details(No,SNo,KSNo,AccountID,Account,CostCentreID,Description,Amount,Tax)
	select fd.No,0 SNo,fd.SNo KSNo,fd.AccountID,a.Name Account,fd.CostCentreID,fd.Description,fd.Amount,fd.Tax from aJournalDtl fd 
	join aAccount a on fd.AccountID=a.ID 
	where fd.CompanyID=@CompanyID and fd.PeriodID=@PeriodID and  fd.No=@No

	update d set d.CostCentre=c.Name from @Details d join aCostCentre c on d.CostCentreID=c.ID

	update d set d.TaxP=case when DrCr=1 then -1 else 1 end*t.Rate from @Details d join aAccount a on d.AccountID=a.ID join aTaxGroup t on a.TaxGroupID=t.ID join @Header h on d.No=h.No

	select *,Amount+isnull(Tax,0)NetAmount from @Details order by KSNo

End
go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete
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
		   
END

GO

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

declare @Transaction table(Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
declare @CC int
select @BR=BillwiseReceipt,@CC=ChequeClearing from aVoucherTypeSettings

--Cash
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and isnull(t.VoucherTypeID,0) not in(@BR,@CC)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null


--Billwise Receipt
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name




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


if object_id('spGetAccounts') is not null drop proc spGetAccounts

go

create proc spGetAccounts
@CompanyID int,
@Status tinyint=null,
@UserId int=1,
@PeriodId int=null

as

set nocount on
set xact_abort on
set transaction isolation level read uncommitted

declare @Account table (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),UnderAccountID int,AccountSubGroupId int,Balance float)

declare @Secret bit
if object_id('invUser') is not null
	select @Secret=Secret from aUser au join invUser iu on au.Id=iu.amsUserId where iu.Id=@UserId

insert @Account(ID,Code,Name,UnderAccountID,AccountSubGroupId)
select ID,Code,Name,UnderAccountID,AccountSubGroupId from aAccount where ModuleID is null and (Secret is null or Secret=0 or @Secret=1)


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float,
 IncomeOrExpense bit
)

insert #Balance(Level,AccountID,IncomeOrExpense) 
select c1.ID,c1.ID,case when g.AccountTypeID=4 or g.AccountTypeID=5 then 1 end from @Account c1 
join aAccountSubGroup sg on c1.AccountSubGroupId=sg.Id
join aAccountGroup g on sg.AccountGroupId=g.Id
left join @Account c2 on c1.UnderAccountID=c2.ID 
where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID,IncomeOrExpense)
	select b.Level +'*'+cast(a.ID as varchar),a.ID,b.IncomeOrExpense from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End

if @PeriodId is null
	select @PeriodId=Id from aPeriod where convert(varchar,current_timestamp,112) between [From] and [To]

declare @CFIE bit
select @CFIE=CarryForwardIncomeExpense from aOption


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID and (v.CompanyID=@CompanyID or @CompanyID=0) and (@CFIE=1 or v.PeriodID is null or v.PeriodID=@PeriodID or b.IncomeOrExpense is null) 
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID and (v.CompanyID=@CompanyID or @CompanyID=0) and (@CFIE=1 or v.PeriodID is null or v.PeriodID=@PeriodID or b.IncomeOrExpense is null)
 )b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID

--Accounts
update c set c.Balance=b.Balance from @Account c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from @Account

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join @Account c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------


if @Status=2-- Balance<>0
	delete @Account where Balance is null or Balance=0



select ID,Code,Name,Balance from @Account order by Name

go

if object_id('spTradingIncomes') is not null drop proc spTradingIncomes
go
create proc spTradingIncomes
@CompanyID int,  
@FromDate int,  
@ToDate int,
@CostCentreId int=0
  
as  
  
set nocount on  
set transaction isolation level read uncommitted

create table #Incomes(Ord int,AOrd int,[Group] nvarchar(50),Particulars nvarchar(100),Amount float,VtypeId int)  

create table #aTransaction(VoucherTypeId int,DebtorId int,CreditorId int,Amount float)

declare @DefaultCostCentreId int
select @DefaultCostCentreId=CostCentreId from aOption

declare @StartDate int
select @StartDate=min([From]) from aPeriod

insert #aTransaction(VoucherTypeId,DebtorId,CreditorId,Amount)
select VoucherTypeId,DebtorId,CreditorId,Amount from aTransaction 
where (@CompanyID=0 or CompanyID=@CompanyID)
and (Date is null and @FromDate<@StartDate or Date between @FromDate and @ToDate)
and (@CostCentreId=0 or isnull(CostCentreId,@DefaultCostCentreId)=@CostCentreId)

declare @OptCompanyId int
set @OptCompanyId=@CompanyID
if @OptCompanyId=0
	select @OptCompanyId=min(Id) from aCompany


----Sales  
--declare @SalesGroupID int,@SalesGroup nvarchar(100)  
--select @SalesGroupID=Sales,@SalesGroup=a.Name from aSubGroupSettings s join aAccountSubGroup a on s.Sales=a.ID  
  
--insert #Incomes([Group],Particulars,Amount)   
--select @SalesGroup,a.Name,sum(Amount) from #aTransaction t join aAccount a on t.CreditorID=a.ID   
--where a.AccountSubGroupID=@SalesGroupID group by a.Name  
  
--insert #Incomes([Group],AOrd,Particulars,Amount)   
--select @SalesGroup,1,'Less Return/Tax/ROff/Others',-sum(Amount) from #aTransaction t join aAccount a on t.DebtorID=a.ID   
--where a.AccountSubGroupID=@SalesGroupID having sum(Amount) is not null  
 
 --Sales  
declare @SalesGroupID int,@SalesGroupName nvarchar(100),@SundryCreditors int,@CIH int,@SundryDebtors int 
select @SalesGroupID=Sales,@SalesGroupName=a.Name,@SundryCreditors=s.SundryCreditors,@CIH=s.CashInHand,@SundryDebtors=s.SundryDebtors from aSubGroupSettings s join aAccountSubGroup a on s.Sales=a.ID  

declare @VTD table(Name varchar(50),AccountVtypeId int)

if object_id('invVoucherTypeDetails') is not null
	insert @VTD
	select Name,AccountVtypeId from invVoucherTypeDetails

if object_id('phyVoucherTypeDetails') is not null
	insert @VTD
	select Name,AccountVtypeId from phyVoucherTypeDetails

insert #Incomes([Group],Particulars,Amount,VtypeId)   
select @SalesGroupName,case when d.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then c.Name else d.Name end + isnull(' ('+ v.Name +')',''),sum(Amount),t.VoucherTypeId from #aTransaction t 
join aAccount c on t.CreditorID=c.ID   
join aAccount d on t.DebtorId=d.Id
left join @VTD v on t.VoucherTypeId=v.AccountVtypeID
where c.AccountSubGroupID=@SalesGroupID 
group by case when d.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then c.Name else d.Name end,v.Name,t.VoucherTypeId
having sum(Amount) is not null  

insert #Incomes([Group],Particulars,Amount,VtypeId)   
select @SalesGroupName,case when c.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then d.Name else c.Name end + isnull(' ('+ v.Name +')',''),-sum(Amount),t.VoucherTypeId from #aTransaction t 
join aAccount d on t.DebtorID=d.ID   
join aAccount c on t.CreditorID=c.ID
left join @VTD v on t.VoucherTypeId=v.AccountVtypeID
where d.AccountSubGroupID=@SalesGroupID 
group by case when c.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then d.Name else c.Name end,v.Name,t.VoucherTypeId  

--Closing Stock  
if exists(select 1 from sysobjects where name='invOption')  
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin  
		declare @Stock float  
		if exists(select 1 from invOption where StockCalculation=2 and CompanyId=@OptCompanyId)--SerialNowise
		Begin
			set @Stock=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=@ToDate,@Type=@Stock output  

		End
		Else
		Begin
			declare @invCostCentreId int
		    set @invCostCentreId=0
		    select @invCostCentreId=Id from invCostCentre where CostCentreId=@CostCentreId
			if (@CompanyID=0)
			Begin
				declare @CId int
				declare @CStock float
				set @CId=0
				while exists(select Id from aCompany where Id>@CID)
				Begin
					select top 1 @CId=Id from aCompany where Id>@CId
					set @CStock=null
					exec spStock @CompanyID=@CId,@CostCentreId=@invCostCentreId,@ToDate=@ToDate,@Type=@CStock output
					set @Stock=isnull(@Stock,0)+isnull(@CStock,0)
				End
			End
			Else
				exec spStock @CompanyID=@CompanyID,@CostCentreId=@invCostCentreId,@ToDate=@ToDate,@Type=@Stock output  
		End

		if isnull(@Stock,0)<>0
			insert #Incomes(Ord,Particulars,Amount)   
			values(2,'CLOSING STOCK',@Stock)  

	End  
End

if exists(select 1 from sysobjects where name='prOptStockValue')  
begin
   declare @Stock1 float  
   exec prOptStockValue @CompanyID=@CompanyID,@Date=@ToDate,@Stock=@Stock1 output  
	insert #Incomes(Ord,Particulars,Amount)   
	values(0,'CLOSING STOCK',@Stock1)  
end


  
if exists(select 1 from sysobjects where name='prPhyStockValue')  
begin
   declare @Stock2 float  
   exec prPhyStockValue @CompanyID=@CompanyID,@Date=@ToDate,@Stock=@Stock2 output  
   insert #Incomes(Ord,Particulars,Amount)   
   values(0,'CLOSING STOCK',@Stock2)  
end
  
if exists(select 1 from sysobjects where name='prWpyStockValue')  
begin
   declare @Stock3 float  
   exec prWpyStockValue @CompanyID=@CompanyID,@Date=@ToDate,@Stock=@Stock3 output  
   insert #Incomes(Ord,Particulars,Amount)   
   values(0,'CLOSING STOCK',@Stock3)  
end


--Direct Incomes  
declare @DirectIncomeID int,@DirectIncomeGroup nvarchar(100)  
select @DirectIncomeID=DirectIncome,@DirectIncomeGroup=a.Name from aSubGroupSettings s join aAccountSubGroup a on s.DirectIncome=a.ID  
  
insert #Incomes(Ord,[Group],Particulars,Amount)   
select 2,@DirectIncomeGroup,a.Name,sum(Amount) from #aTransaction t join aAccount a on t.CreditorID=a.ID   
where a.AccountSubGroupID=@DirectIncomeID group by a.Name  


insert #Incomes(Ord,[Group],Particulars,Amount)   
select 2,@DirectIncomeGroup,a.Name,-sum(Amount) from #aTransaction t join aAccount a on t.DebtorID=a.ID   
where a.AccountSubGroupID=@DirectIncomeID group by a.Name  

--select [Group],Particulars,sum(Amount)Amount from #Incomes group by [Group],Particulars,Ord,AOrd order by Ord,AOrd

select * from 
(select Ord,[Group],VtypeId,Particulars,sum(Amount)Amount from #Incomes group by Ord,[Group],VtypeId,Particulars)a
Order by Ord,[Group],VtypeId,abs(Amount)desc
  
go  

if object_id('spTradingExpenses') is not null drop proc spTradingExpenses

go

create proc spTradingExpenses
@CompanyID int,  
@FromDate int,  
@ToDate int,  
@Level tinyint=0,
@Type int=0,
@CostCentreId int=0
as  
  
set nocount on  
set transaction isolation level read uncommitted 

create table #Expenses(Ord tinyint,[Group] nvarchar(50),ID int,Particulars nvarchar(100),Amount float,Level tinyint,VtypeId int)  

declare @Date int  
set @Date = CONVERT(VARCHAR,CAST(CAST(@FromDate AS VARCHAR(100)) AS DATETIME) -1,112)

declare @OptCompanyId int
set @OptCompanyId=@CompanyID
if @OptCompanyId=0
	select @OptCompanyId=min(Id) from aCompany


--Opening Stock  
if exists(select 1 from sysobjects where name='invOption')  
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin  
		declare @Stock float  

		if exists(select 1 from invOption where StockCalculation=2 and CompanyId=@OptCompanyId)--SerialNowise
		Begin
			--declare @SType float
			--set @SType=0
			--exec prIMIStockReport @CompanyID=@CompanyID,@Date=@Date,@Type=@SType output
			--set @Stock=isnull(@Stock,0)+isnull(@SType,0)
			set @Stock=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=@Date,@Type=@Stock output

		End
		Else
		Begin
			declare @invCostCentreId int
			set @invCostCentreId=0
			select @invCostCentreId=Id from invCostCentre where CostCentreId=@CostCentreId
			exec spStock @CompanyID=@CompanyID,@CostCentreID=@invCostCentreId,@ToDate=@Date,@Type=@Stock output  	
		End


		if isnull(@Stock,0)<>0
			insert #Expenses(Particulars,Amount)   
			values('OPENING STOCK',@Stock)  
	End  
End


if exists(select 1 from sysobjects where name='prOptStockValue')  
begin
   declare @Stock1 float  
   exec prOptStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock1 output  
   insert #Expenses(Particulars,Amount)   
 values('OPENING STOCK',@Stock1) 
end


if exists(select 1 from sysobjects where name='prPhyStockValue')  
begin
   declare @Stock2 float  
   exec prPhyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock2 output  
   insert #Expenses(Particulars,Amount)   
   values('OPENING STOCK',@Stock2) 
end

if exists(select 1 from sysobjects where name='prWpyStockValue')  
begin
   declare @Stock3 float  
   exec prWpyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock3 output  
   insert #Expenses(Particulars,Amount)   
   values('OPENING STOCK',@Stock3) 
end


create table #aTransaction(VoucherTypeId int,DebtorId int,CreditorId int,AccountId int,Amount float)

declare @DefaultCostCentreId int
select @DefaultCostCentreId=CostcentreId from aOption

declare @StartDate int
select @StartDate=min([From]) from aPeriod


insert #aTransaction(VoucherTypeId,DebtorId,CreditorID,AccountId,Amount)
select VoucherTypeId,DebtorId,CreditorID,AccountId,Amount from aTransaction 
where (@CompanyID=0 or CompanyID=@CompanyID)
and (Date is null and @FromDate<@StartDate or Date between @FromDate and @ToDate) 
and (@CostCentreId=0 or isnull(CostCentreId,@DefaultCostCentreId)=@CostCentreId)

if (@Type=1)--W/O PDC
Begin
	declare @PDCP int
	select @PDCP=PDCPayable from aAccountSettings where CompanyId=@OptCompanyId

	delete #aTransaction where CreditorId=@PDCP and AccountId is not null
	insert #aTransaction(DebtorId,CreditorID,Amount)
	select AccountId,CreditorId,Amount from #aTransaction where DebtorId=@PDCP and AccountId is not null
End

--Purchase  
declare @PurchaseGroupID int,@PurchaseGroupName nvarchar(100),@SundryCreditors int,@CIH int,@SundryDebtors int 
select @PurchaseGroupID=Purchase,@PurchaseGroupName=a.Name,@SundryCreditors=s.SundryCreditors,@CIH=s.CashInHand,@SundryDebtors=s.SundryDebtors from aSubGroupSettings s join aAccountSubGroup a on s.Purchase=a.ID  

declare @VTD table(Name varchar(50),AccountVtypeId int)

if object_id('invVoucherTypeDetails') is not null
	insert @VTD
	select Name,AccountVtypeId from invVoucherTypeDetails

if object_id('phyVoucherTypeDetails') is not null
	insert @VTD
	select Name,AccountVtypeId from phyVoucherTypeDetails

insert #Expenses([Group],Particulars,Amount,VtypeId)   
select @PurchaseGroupName,case when c.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then d.Name else c.Name end + isnull(' ('+ v.Name +')',''),sum(Amount),t.VoucherTypeId from #aTransaction t 
join aAccount d on t.DebtorID=d.ID   
join aAccount c on t.CreditorID=c.ID
left join @VTD v on t.VoucherTypeId=v.AccountVtypeID
where d.AccountSubGroupID=@PurchaseGroupID 
group by case when c.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then d.Name else c.Name end,v.Name,t.VoucherTypeId  


insert #Expenses([Group],Particulars,Amount,VtypeId)   
select @PurchaseGroupName,case when d.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then c.Name else d.Name end + isnull(' ('+ v.Name +')',''),-sum(Amount),t.VoucherTypeId from #aTransaction t 
join aAccount c on t.CreditorID=c.ID   
join aAccount d on t.DebtorId=d.Id
left join @VTD v on t.VoucherTypeId=v.AccountVtypeID
where c.AccountSubGroupID=@PurchaseGroupID 
group by case when d.AccountSubGroupId in(@SundryCreditors,@SundryDebtors,@CIH) then c.Name else d.Name end,v.Name,t.VoucherTypeId
having sum(Amount) is not null  
  


--Direct Expenses  
declare @DirectExpenseID int,@DirectExpenseName nvarchar(100)  
select @DirectExpenseID=DirectExpense,@DirectExpenseName=a.Name from aSubGroupSettings s join aAccountSubGroup a on s.DirectExpense=a.ID  
  
create table #Account(ID int,Name nvarchar(100),UnderAccountID int,Level tinyint)  
insert #Account  
select ID,Name,UnderAccountID,0 from aAccount where AccountSubGroupID=@DirectExpenseID and (UnderAccountID is null or ID=UnderAccountID)  
  
  
--Drilling for Under Accounts  
while @@rowcount>0  
 insert #Account  
 select a1.ID,a1.Name,a1.UnderAccountID,a2.Level+1 from aAccount a1   
 join #Account a2 on a1.UnderAccountID=a2.ID   
 left join #Account a3 on a1.ID=a3.ID  
 where a3.ID is null  
  

  
insert #Expenses(Ord,[Group],ID,Particulars,Amount,Level)   
select 2,@DirectExpenseName,a.ID,a.Name,sum(Amount),a.Level from #aTransaction t join #Account a on t.DebtorID=a.ID   
group by a.ID,a.Name,a.Level  


insert #Expenses(Ord,[Group],ID,Particulars,Amount,Level)   
select 2,@DirectExpenseName,a.ID,a.Name,-sum(Amount),a.Level from #aTransaction t join #Account a on t.CreditorID=a.ID  
group by a.ID,a.Name,a.Level  

  
--Climbing for Levels  
while exists(select top 1 1 from #Expenses where Level>@Level)  
Begin  
 update t set t.ID=a.UnderAccountID,t.Particulars=u.Name,t.Level=t.Level-1 from #Expenses t join #Account a on t.ID=a.ID join #Account u on a.UnderAccountID=u.ID where a.UnderAccountID is not null and t.Level>@Level  
End  
  
select * from 
(select Ord,[Group],VtypeId,ID,Particulars,sum(Amount)Amount from #Expenses group by Ord,[Group],VtypeId,ID,Particulars)a
Order by Ord,[Group],VtypeId,abs(Amount)desc
  
go

if object_id('triggeraTransaction') is not null drop trigger triggeraTransaction

go

CREATE TRIGGER triggeraTransaction ON aTransaction
--WITH EXECUTE AS CALLER
--INSTEAD OF DELETE
for delete,update
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

if object_id('spGetNetProfit') is not null 
	drop proc spGetNetProfit

go

create proc spGetNetProfit
@CompanyID int,
@CostCentreId int=0,
@Date int,
@NP float out,
@SM float=null out,
@Stock float=null out,
@FromDate int=0

as

set nocount on
set transaction isolation level read uncommitted

declare @StartDate int
select @StartDate=min([From]) from aPeriod

--Net Profit/Loss

select @NP=isnull(sum(tr.Amount),0) from aTransaction tr 
join aAccount a on tr.CreditorID=a.ID
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
--where (tr.Date is null or tr.Date<=@Date)
where isnull(tr.Date,20000101) between @FromDate and @Date
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreID=0 or tr.CostCentreID=@CostCentreID)
and (g.AccountTypeID=4 or g.AccountTypeID=5) 

select @NP=@NP-isnull(sum(tr.Amount),0) from aTransaction tr 
join aAccount a on tr.DebtorID=a.ID
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
--where (tr.Date is null or tr.Date<=@Date)
where isnull(tr.Date,20000101) between @FromDate and @Date
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreID=0 or tr.CostCentreID=@CostCentreID)
and (g.AccountTypeID=4 or g.AccountTypeID=5) 



declare @OptCompanyId int
if @CompanyId=0 
	select  @OptCompanyId=min(Id) from aCompany
else
	set @OptCompanyId=@CompanyId


if exists(select 1 from sysobjects where name='invOption')
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin  
		--Opening Stock
		declare @ToDate int  
		set @ToDate = CONVERT(VARCHAR,CAST(CAST(@FromDate AS VARCHAR(100)) AS DATETIME) -1,112)

		exec spStock @CompanyID=@CompanyID,@CostCentreID=@CostCentreID,@ToDate=@ToDate,@Type=@Stock output
		if exists(select 1 from invOption where StockCalculation=2)--SerialNowise
		Begin
			declare @Type float
			set @Type=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=0,@Type=@Type output
			set @Stock=isnull(@Stock,0)+isnull(@Type,0)
		End	
	
		set @NP=@NP-isnull(@Stock,0)
		set @SM=isnull(@Stock,0)


		--Closing Stock
		set @Stock=NULL
		if (@CompanyID=0)
			Begin
				declare @CId int
				declare @CStock float
				set @CId=0
				while exists(select Id from aCompany where Id>@CID)
				Begin
					select top 1 @CId=Id from aCompany where Id>@CId
					set @CStock=null
					exec spStock @CompanyID=@CId,@CostCentreId=@CostCentreId,@ToDate=@Date,@Type=@CStock output
					set @Stock=isnull(@Stock,0)+isnull(@CStock,0)
				End
			End
		Else
			exec spStock @CompanyID=@CompanyID,@CostCentreID=@CostCentreID,@ToDate=@Date,@Type=@Stock output

		if exists(select 1 from invOption where StockCalculation=2)--SerialNowise
		Begin
			set @Type=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=@Date,@Type=@Type output
			set @Stock=isnull(@Stock,0)+isnull(@Type,0)
		End	
	
		set @NP=@NP+isnull(@Stock,0)
		set @SM=isnull(@Stock,0)-isnull(@SM,0)
	End
End

if exists(select 1 from sysobjects where name='prPhyStockValue')  
Begin  
	set @Stock=NULL   
	exec prPhyStockValue @CompanyID=@CompanyID,@Date=@FromDate,@Stock=@Stock output
	set @NP=@NP-isnull(@Stock,0)  
	set @SM=isnull(@Stock,0)-isnull(@SM,0)

	set @Stock=NULL   
	exec prPhyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock output
	set @NP=@NP+isnull(@Stock,0)  
	set @SM=isnull(@Stock,0)-isnull(@SM,0)
End  

if exists(select 1 from sysobjects where name='prWpyStockValue')  
Begin
	set @Stock=NULL   
	exec prWpyStockValue @CompanyID=@CompanyID,@Date=@FromDate,@Stock=@Stock output
	set @NP=@NP-isnull(@Stock,0)  
	set @SM=isnull(@Stock,0)-isnull(@SM,0)

	set @Stock=NULL   
	exec prWpyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock output
	set @NP=@NP+isnull(@Stock,0)  
	set @SM=isnull(@Stock,0)-isnull(@SM,0)
End  

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


insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,sum(tr.Amount) from aTransaction tr 
join @Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,-sum(tr.Amount) from aTransaction tr 
join @Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

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
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(OB)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@CompanyID or @CompanyID=0

exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=@FromDate,@Date=@Date,@NP=@NP output

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount)
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(Period)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@CompanyID or @CompanyID=0



---------------------

--Closing Stock
if exists(select 1 from sysobjects where name='spStock')
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@CompanyId)
	Begin 
		declare @Stock float
		exec spStock @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@ToDate=0,@Type=@Stock output
		
		insert @Liabilities(Type,[Group],SubGroup,Account,NameInOL,Amount)
		select top 1 a.Type,a.[Group],a.SubGroup,a.Name,a.NameInOL,@Stock from aAccountType t 
		join aAccountSettings st on st.CompanyId=@CompanyId or @CompanyId=0
		join @Account a on st.OpeningBalanceEquity=a.ID
	End
End


if exists(select 1 from sysobjects where name='prPhyStockValue')  
Begin  
  set @Stock=NULL   
  exec prPhyStockValue @CompanyID=@CompanyID,@Date=20000101,@Stock=@Stock output
  insert @Liabilities(Type,[Group],SubGroup,Account,NameInOL,Amount)
  select top 1 a.Type,a.[Group],a.SubGroup,a.Name,a.NameInOL,@Stock from aAccountType t 
  join aAccountSettings st on st.CompanyId=@CompanyId or @CompanyId=0
  join @Account a on st.OpeningBalanceEquity=a.ID
End  


select Type,[Group],SubGroup,Account,NameInOL,sum(Amount)Amount from @Liabilities group by Type,[Group],SubGroup,Account,NameInOL having sum(Amount)<>0

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
	update t set t.AccountID=a.UnderAccountID from #TB t join #Account a on t.AccountID=a.iD where a.UnderAccountID is not null
	set @Level=@Level-1
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

declare @Transaction table(Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
declare @CC int
select @BR=BillwiseReceipt,@CC=ChequeClearing from aVoucherTypeSettings

--Cash
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
and isnull(t.VoucherTypeID,0) not in(@BR,@CC)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null


--Billwise Receipt
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name




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

declare @Transaction table(Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
select @BR=BillwiseReceipt,@CR=ChequeReceipt from aVoucherTypeSettings

--Cash
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
--and isnull(t.VoucherTypeID,0) not in(@BR,@CC)
and isnull(t.VoucherTypeID,0) not in(@BR,@CR)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null



--Billwise Receipt
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name




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


if OBJECT_ID('spSaveBillwiseReceipt') is not null drop proc spSaveBillwiseReceipt

go

create proc spSaveBillwiseReceipt
@No int,
@RefNo nvarchar(50),
@Date int,
@DebtorID int,
@CustomerID int,
@Amount float,
@Advance float,
@ChequeNo varchar(25),
@ChequeDate int=null,
@Description nvarchar(100),
@CostCentreId int=null,
@SalesmanId int=null,
@xml xml,
@CompanyID int,
@PeriodID int,
@PaymentType int=0
as

set nocount on
set xact_abort on

Begin Transaction

set @CustomerID=isnull(@CustomerID,0)

--Header
if @No=0
Begin
	select @No=isnull(max(No),0)+1 from aBillwiseReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID

	insert aBillwiseReceiptHdr([No],RefNo,Date,DebtorID,CustomerID,Amount,Advance,Description,CostCentreId,CompanyID,PeriodID,PaymentType,SalesmanID)
	values(@No,nullif(@RefNo,''),@Date,@DebtorID,@CustomerID,nullif(@Amount,0),nullif(@Advance,0),nullif(@Description,''),@CostCentreId,@CompanyID,@PeriodID,@PaymentType,@SalesmanID)
End
else
	update aBillwiseReceiptHdr set RefNo=nullif(@RefNo,''),Date=@Date,DebtorID=@DebtorID,CustomerID=@CustomerID,Amount=nullif(@Amount,0),Advance=nullif(@Advance,0),CostCentreId=@CostCentreId,Description=@Description,PaymentType=@PaymentType,SalesmanID=@SalesmanID
	where [No]=@No and CompanyID=@CompanyID and PeriodID=@PeriodID


--Details
delete aBillwiseReceiptDtl where No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

declare @Dtl table(EPeriodID int,EVoucherTypeID int,ENo int,ESNo int,Amount float,Paid float,Discount float)

declare @idoc int
exec sp_xml_preparedocument @idoc output,@xml

insert @Dtl(EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount)
select nullif(EPeriodID,0),nullif(EVoucherTypeID,0),nullif(ENo,0),nullif(ESNo,0),Amount,nullif(Paid,0),nullif(Discount,0) from openxml(@idoc, '/DetailsTable/Table1',2)
with
(
EPeriodID int '@PeriodID',
EVoucherTypeID int '@VoucherTypeID',
ENo int '@No',
ESNo int '@SNo',
Amount float '@Amount',
Paid float '@Paid',
Discount float '@Discount'
) 
where Paid<>0 or Discount<>0

exec sp_xml_removedocument @idoc

insert aBillwiseReceiptDtl(No,EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount,CompanyID,PeriodID)
select @No,EPeriodID,EVoucherTypeID,ENo,ESNo,Amount,Paid,Discount,@CompanyID,@PeriodID from @Dtl


--Posting
declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

delete aTransaction where VoucherTypeID=@VoucherTypeID and No=@No and CompanyID=@CompanyID and PeriodID=@PeriodID

if @PaymentType=1
Begin
	declare @PDCReceivable int
	if len(rtrim(@ChequeNo))>0
	Begin
		select @PDCReceivable=PDCReceivable from aAccountSettings where CompanyID=@CompanyID
		insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CNo,CDate,AccountID,CostCentreId)
		values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@PDCReceivable,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@ChequeNo,@ChequeDate,@DebtorID,@CostCentreId)
	End
	Else
		insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreId,CDate)
		values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorId,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@CostCentreId,@ChequeDate)
		
End
else if @PaymentType=2
Begin
	declare @CreditCardId int
	select @CreditCardId=Id from aCreditCard where AccountId=@DebtorID
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CNo,CostCentreId,CreditCardId)
	values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorID,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@ChequeNo,@CostCentreId,@CreditCardId)
End
Else
	insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,Description,RefNo,CostCentreId)
	values(@CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DebtorID,@CustomerID,@Amount,nullif(@Description,''),@RefNo,@CostCentreId)


--Discount
declare @DiscountPaid int
select @DiscountPaid=DiscountPaid from aAccountSettings where CompanyID=@CompanyID

insert aTransaction(CompanyID,PeriodID,Date,VoucherTypeID,No,DebtorID,CreditorID,Amount,RefNo,CostCentreId)
select @CompanyID,@PeriodID,@Date,@VoucherTypeID,@No,@DiscountPaid,@CustomerID,sum(Discount),@RefNo,@CostCentreId from @Dtl having sum(Discount)<>0


Commit
	
select @No 



go

if OBJECT_ID ('spGetNextRefNo')is not null drop proc spGetNextRefNo

go

create proc spGetNextRefNo
@CompanyID int=1,
@PeriodID int,
@VoucherTypeID int
as

if exists(select 1 from aOption where ManualRefNo=1)
	return

declare @Prefix varchar(50)    
declare @Size int    
declare @RefNo varchar(50)

select @Prefix=isnull(max(Left(RefNo, LEN(RefNo)-PatIndex('%[^0-9]%', REVERSE(RefNo) + '1')+1)),''),@Size=isnull(max(len(RefNo)),0) from aTransaction where CompanyID=@CompanyID and PeriodID=@PeriodID and VoucherTypeID=@VoucherTypeID and isnumeric(RefNo)=0
select @RefNo=isnull(max(cast(replace(RefNo,@Prefix,'') as numeric)),0)+1 from aTransaction where CompanyID=@CompanyID and PeriodID=@PeriodID and VoucherTypeID=@VoucherTypeID and PATINDEX('%[^0-9]%',replace(RefNo,@Prefix,''))=0 and len(replace(RefNo,@Prefix,''))>0 and RefNo like @Prefix+'%'
if len(@Prefix+@RefNo)>@Size set @Size=len(@Prefix+@RefNo)
select @Prefix+replicate('0',@Size-len(@Prefix+@RefNo))+@RefNo  

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

if object_id('spCustomersAgeing') is not null drop proc spCustomersAgeing

go

create proc spCustomersAgeing 
@CompanyId int=1,
@ToDate int,
@AccountID int=0,
@Type tinyint, --0 Summary,1 Detailed
@From int=null,
@To int=null,
@SalesmanID int=null,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null,
@CostCentreId int=0

as

  set nocount on
  set transaction isolation level read uncommitted

  create table #Due 
  (SNo int,
   ID numeric ,
   Date int null default 0,
   VtypeID int,
   No int,
   Description nvarchar(200),
   Amount money
  )

  declare @FinalDue table
  (ID numeric ,
   Date int null default 0,
   SNo int,
   Rsales float ,
   TotReceived float ,
   Balance float )


   create table #Account (ID int,Name nvarchar(100),UnderAccountID int,Phone varchar(100))
   insert #Account(Id,Name,UnderAccountId) 
   select a.ID,a.name,a.ID from aAccount a join aSubGroupSettings sg on a.AccountSubGroupID=sg.SundryDebtors where	a.ID=@AccountID

   --Drilling for Under Accounts,
	--while @Type in(1,2) and @@rowcount>0
		insert #Account(Id,Name,UnderAccountId) 
		select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
		join #Account a2 on a1.UnderAccountID=a2.ID 
		left join #Account a3 on a1.ID=a3.ID
		where a3.ID is null
   
	
	if @SalesmanID>0
		delete a from #Account a join invCustomer c on a.ID=c.AccountID where c.SalesmanID<>@SalesmanID or c.SalesmanID is null
 
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
		delete t1 from #Account t1 
		left outer join @T1 t2 on t1.ID = t2.Id 
		where t2.Id is null
	  end
	end 


	--Active
	if @Status in (0,1)
	Begin
		if object_id('invCustomer') is not null
		Begin
			delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
		end
	End
	

  --Phone
  update a set a.Phone=isnull(nullif(c.Phone,''),c.MobileNo) from #Account a join invCustomer c on a.ID=c.AccountID

  
  /*Amount*/
  insert #Due(SNo,ID,Date,VTypeID,No,Description,Amount) 
  select row_number()over(order by Date,No)SNo, DebtorID,Date,d.VoucherTypeID,isnull(No,0),d.Description,sum(Amount) from aTransaction d 
  join #Account a on a.ID=d.DebtorID 
  where (CompanyID=@CompanyId or @CompanyId=0)
  and (date <= @ToDate or Date is null) 
  and (CostCentreId=@CostCentreId or @CostCentreId=0)
  group by DebtorID,PeriodID,date,d.VoucherTypeID,d.No,d.Description

  
  insert @FinalDue (ID,Date,SNo,RSales) 
  select d.ID,dd.date,dd.SNo,sum(d.Amount) from #Due d
  join (select date,SNo,ID from #Due)dd
  on d.ID = dd.ID and d.SNo <= dd.SNo
  group by d.ID,dd.SNo,dd.date

  --Receipts
  declare @aTransaction table(VoucherTypeID int,CNo varchar(50),DebtorId int,CreditorId int,AccountId int,Date int,CompanyId int,Amount float)
  insert @aTransaction
  select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
  from aTransaction d join #Account a on a.id=d.CreditorID 
  where (date <=@ToDate or Date is null) 
  and (CompanyId=@CompanyId or @CompanyId=0)
  and (CostCentreId=@CostCentreId or @CostCentreId=0)

  

	if @Type=3 --W/O PDC
	Begin
		declare @CQR int,@CQP int,@CQC int,@BR int,@BP int
		select @CQR=ChequeReceipt,@CQP=ChequePayment,@CQC=ChequeClearing,@BR=BillwiseReceipt,@BP=BillwisePayment from aVoucherTypeSettings

		delete @aTransaction where VoucherTypeID in(@CQR,@CQP,@BR,@BP) and CNo is not null

		--To Insert Cleared
		insert @aTransaction
		select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
		from aTransaction d join #Account a on a.id=d.AccountID 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		--To Insert Bounced
		insert @aTransaction
		select VoucherTypeID,CNo,CreditorId,DebtorId,AccountId,Date,CompanyId,Amount
		from aTransaction d 
		join #Account a on a.id=d.DebtorId 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		declare @PDCP int,@PDCR int
		select @PDCP=PDCPayable,@PDCR=PDCReceivable from aAccountSettings where CompanyID=@CompanyId
	
		update @aTransaction set DebtorID=AccountID,AccountID=null where (DebtorID=@PDCP or DebtorID=@PDCR)
		update @aTransaction set CreditorID=AccountID,AccountID=null where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID<>AccountID
		
		
	End

  update r set r.totreceived = d.Amount from @FinalDue r join
  (select CreditorID,sum(Amount)Amount from @aTransaction group by CreditorID) d on d.CreditorID = r.ID

  delete from @FinalDue where round(RSales,1) <= round(isnull(TotReceived,0),1)

  delete d from #Due d left join @FinalDue f on d.ID=f.ID and d.SNo=f.SNo where f.SNo is null
  
  if not exists(select * from @FinalDue where RSales>isnull(TotReceived,0)) delete #Due

  update @FinalDue set Balance = RSales - isnull(TotReceived,0)

  declare @MinNo table(ID int,SNo int)
  insert @MinNo select ID,min(SNo) from @FinalDue group by ID

  delete d from #Due d join @MinNo m on d.ID = m.ID and d.SNo < m.SNo
  update d set d.Amount = f.balance from #Due d join @MinNo m on d.ID = m.ID and m.SNo = d.SNo join @FinalDue f on f.ID = m.ID and m.SNo = f.SNo
  ---------------

  --For calculating age, no future date need to consider
  if @ToDate>convert(varchar,current_timestamp,112) 
	  set @ToDate=convert(varchar,current_timestamp,112)


  --Filtering days
  if @From is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<@From 

  if @To is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))>@To
  ----
  
  
  declare @Line varchar(13)
  set @Line=REPLICATE('_',13)

  declare @AI int
  select @AI=AgeInterval from aOption
  
  declare @1C varchar(max)
  select @1C=cast(@AI+1 as varchar)+'-'+cast(2*@AI as varchar)

  declare @2C varchar(max)
  select @2C=cast(2*@AI+1 as varchar)+'-'+cast(3*@AI as varchar)

  declare @3C varchar(max)
  select @3C=cast(3*@AI+1 as varchar)+'-'+cast(4*@AI as varchar)

  declare @4C varchar(max)
  select @4C=cast(4*@AI+1 as varchar)+'-'
  
  declare @DecimalFormat int
  select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption	

  if @Type in(1,2,3)
  Begin	
	
	--Balance
	declare @DueBal table(Ord int,ID int,Date int null default 0,VtypeID int,No int,Description nvarchar(200),Amount money,Balance money)
	
	insert @DueBal
    select row_number() over (partition by ID order by ID,Date),ID,Date,VtypeID,No,Description,Amount,null from #Due
	
	
	;with b as
	(select b.Ord,b.id,sum(s.Amount) Balance from @DueBal b join @DueBal s on s.id=b.id and s.Ord<=b.Ord group by b.Ord,b.id)

	update s set s.Balance=b.Balance from @DueBal s join b on b.id=s.id and s.Ord=b.Ord
	---------------------
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)

	Begin
	 		
		create table #FBal(Ord int,ID int,LedgerAccount nvarchar(100),Date int,VtypeID int,No int,Description nvarchar(200),Amount varchar(50),Age varchar(25),Balance varchar(50),Name nvarchar(100),Days int)
		 
		insert #FBal(Ord,ID,Date,VtypeID,No,Description,Amount,Age,Balance)
		select Ord,ID,Date,VtypeID,No,Description,
		convert(varchar,cast(Amount as money),4),
		datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)),
		convert(varchar,cast(Balance as money),4) from @DueBal

		
		insert #FBal(Ord,ID,Amount,Balance)
		select max(Ord)+1,ID,@Line,@Line from @DueBal group by ID 

		insert #FBal(Ord,ID,Amount)
		select max(Ord)+2,ID,convert(varchar,cast(sum(Amount) as money),4) from @DueBal group by ID 

		declare @AL int
		select @AL=max(len(Name)) from #Account

		declare @DL int
		select @DL=max(len(Description)) from #FBal

		insert #FBal(LedgerAccount,Ord,ID,Description,Age,Amount,Balance)
		select REPLICATE('_',@AL),max(Ord)+3,ID,REPLICATE('_',@DL),REPLICATE('_',5),@Line,@Line from @DueBal group by ID 

		declare @Address table(ID int,Address nvarchar(100),Ord int)
		insert @Address select ID,c.Name,1 from invCustomer c join #Account a on c.AccountID=a.ID
		insert @Address select ID,c.Address1,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address1)>0 group by ID,c.Address1 
		insert @Address select ID,c.Address2,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address2)>0 group by ID,c.Address2 
		insert @Address select ID,c.Address3,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address3)>0 group by ID,c.Address3 
		insert @Address select ID,c.Place,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Place)>0 group by ID,c.Place
		insert @Address select ID,c.Phone,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Phone)>0 group by ID,c.Phone
		insert @Address select ID,c.MobileNo,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.MobileNo)>0 group by ID,c.MobileNo

		update f set f.LedgerAccount=c.Address from #FBal f join @Address c on f.ID=c.ID and f.Ord=c.Ord where LedgerAccount is null
		
		-- Just for Ordering by Name
		update f set f.Name=a.Name from #Account a join #FBal f on f.ID=a.ID
		
		if @Type in(1,3)
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,Age,Amount,Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
		else
		Begin
			update #FBal set Days=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))
			exec('
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,Amount,
			case when Days <='+@AI+' then Amount end[ 0-'+@AI+'] ,
			case when Days between '+@AI+'+1 and 2*'+@AI+' then Amount end[ '+@1C+'],
			case when Days between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end[ '+@2C+'],
			case when Days between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end[ '+@3C+'],
			case when Days >4*'+@AI+' or Date is null then Amount end[ '+@4C+'],
			Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
			')
		End
	End
	Else
	Begin
		if @Type in(1,3)
		Begin
			select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,convert(varchar,cast(d.Amount as money),@DecimalFormat) Amount,datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))Age,convert(varchar,cast(d.Balance as money),@DecimalFormat)Balance from @DueBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			union all
			select null,null,null,null,null,@Line,null,@Line
			union all
			select null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat),null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat) from @DueBal
			union all
			select null,null,null,null,null,@Line,null,@Line
		End
		Else
		Begin	
			;with a as
			(select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,
			 d.Amount Amount,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<31 then Amount end [ 0-30] ,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 31 and 45 then Amount end [ 31-45],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 46 and 60 then Amount end [ 46-60],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 61 and 90 then Amount end [ 61-90],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) > 90 or Date is null then Amount end [ 90-],
			 d.Balance from @DueBal d 
			 left join aVoucherType v on d.VTypeID=v.ID
			 )

			 select Date,VoucherTypeID,VType,No,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-],convert(varchar,Balance,@DecimalFormat)Balance from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 union all
			 select null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat),convert(varchar,sum([ 0-30]),@DecimalFormat),convert(varchar,sum([ 31-45]),@DecimalFormat),convert(varchar,sum([ 46-60]),@DecimalFormat),convert(varchar,sum([ 61-90]),@DecimalFormat),convert(varchar,sum([ 90-]),@DecimalFormat),null from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 
		End
	End
  End
  Else
  Begin
	  update #Due set Date=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))--,Amount=convert(varchar,Amount,@DecimalFormat)
	  
	  exec
	  ('
	  ;with a as	
	  (select a.Name Account,a.Phone,d.* from 
	  (select ID,
	  sum(case when Date <='+@AI+' then Amount end)[ 0-'+@AI+'] ,
	  sum(case when Date between '+@AI+'+1 and 2*'+@AI+' then Amount end)[ '+@1C+'],
	  sum(case when Date between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end)[ '+@2C+'],
	  sum(case when Date between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end)[ '+@3C+'],
	  sum(case when Date >4*'+@AI+' or Date is null then Amount end)[ '+@4C+'],
	  sum(Amount)Total
	  from #Due group by ID)d
	  join #Account a on a.ID = d.ID)

	  select * from
	  (select null Ord,ID,Account,Phone,convert(varchar,[ 0-'+@AI+'],'+@DecimalFormat+')[ 0-'+@AI+'],convert(varchar,[ '+@1C+'],'+@DecimalFormat+')[ '+@1C+'],convert(varchar,[ '+@2C+'],'+@DecimalFormat+')[ '+@2C+'],convert(varchar,[ '+@3C+'],'+@DecimalFormat+')[ '+@3C+'],convert(varchar,[ '+@4C+'],'+@DecimalFormat+')[ '+@4C+'],convert(varchar,Total,'+@DecimalFormat+')Total from a
	  union all
	  select 1,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  union all
	  select 2,null,null,null,convert(varchar,sum([ 0-'+@AI+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@1C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@2C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@3C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@4C+']),'+@DecimalFormat+'),convert(varchar,sum(Total),'+@DecimalFormat+') from a
	  union all
	  select 3,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  )b order by Ord,Account')
  End  

  GO


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

declare @Transaction table(Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
select @BR=BillwiseReceipt,@CR=ChequeReceipt from aVoucherTypeSettings

--Cash
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,isnull(a.Salesman,c.SalesMan),t.Description,sum(case when c.CD=0 then Amount end) Amount,sum(case when c.CD=1 then Amount end) Discount,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name 
from aTransaction t
join @Account a on (t.CreditorID=a.ID or t.AccountID=a.ID)
join aVoucherType v on t.VoucherTypeID=v.ID
join @CD c on t.DebtorID=c.Debtor --Cash+Discount
join aAccount a1 on c.Debtor=a1.ID
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
--and isnull(t.VoucherTypeID,0) not in(@BR,@CC)
and isnull(t.VoucherTypeID,0) not in(@BR,@CR)
group by Date,v.Name,t.No,a.Name,isnull(a.Salesman,c.SalesMan),t.Description,t.VoucherTypeID,t.PeriodID,isnull(a.SalesmanId,c.SalesmanId),a1.Name,cc.Name
having sum(case when c.CD=0 then Amount end) is not null



--Billwise Receipt
insert @Transaction
select Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Description,sum(Amount),null Discount,@BR,t.PeriodID,t.SalesmanId,a1.Name 
from aBillwiseReceiptHdr t
join aVoucherType v on v.ID=@BR
join aAccount a on t.CustomerId=a.Id
join aAccount a1 on t.DebtorId=a1.Id
left join invSalesman s on t.SalesmanId=s.Id
left join aCostCentre cc on t.CostCentreId=cc.Id
where (@CompanyID=0 or t.CompanyID=@CompanyID)
and t.Date between @FromDate and @ToDate
and (@CostCentreID=0 or t.CostCentreID=@CostCentreID)
group by Date,v.Name,t.No,a.Name,s.Name,t.Description,t.PeriodID,t.SalesmanId,a1.Name,cc.Name


--Cash Sales
insert @Transaction
select t.Date,cc.Name,v.Name VType,t.No,a.Name Customer,s.Name,t.Notes,sum(NetTotal),null Discount,v.AccountVtypeId,t.PeriodID,t.SalesmanId,a1.Name
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
group by t.Date,v.Name,t.No,a.Name,s.Name,t.Notes,t.PeriodID,t.SalesmanId,cc.Name,v.AccountVtypeId,a1.Name



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

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
select @BR=BillwiseReceipt,@CR=ChequeReceipt,@CC=ChequeClearing from aVoucherTypeSettings

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
and isnull(t.VoucherTypeID,0) not in(@BR,@CR)
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


if object_id('spGetSalesCollectionSummary') is not null drop proc spGetSalesCollectionSummary

go

create proc spGetSalesCollectionSummary
@CompanyID int,
@FromDate int,
@ToDate int,
@SalesmanID int=0,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null

as

create table #Customer (ID int,Name nvarchar(100))
insert #Customer select AccountID,Name from invCustomer where @SalesmanID=0 or SalesmanID=@SalesmanID

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

create table #aTransaction(Customer nvarchar(100),OB float,Qty float,Debit float,Credit float)

--Trnasactions
insert #aTransaction(Customer,OB,Debit,Credit)
select c.Name,case when Date is null or Date<@FromDate then 1 end,sum(case when t.DebtorID=c.ID then Amount end),sum(case when t.CreditorID=c.ID then Amount end) from aTransaction t
join #Customer c on t.DebtorID=c.ID or t.CreditorID=c.ID
where (t.CompanyID=@CompanyID or @CompanyID=0)
and (t.Date<=@ToDate or t.Date is null)
group by c.Name,case when Date is null or Date<@FromDate then 1 end

--OB
update #aTransaction set OB=isnull(Debit,0)-isnull(Credit,0),Debit=null,Credit=null where OB=1

--Qty
insert #aTransaction(Customer,Qty)
select c.Name,sum(sd.Qty) from invSalesHeader sh
join invSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sh.CustomerID=c.ID
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by c.Name

insert #aTransaction(Customer,Qty)
select c.Name,sum(sd.Qty) from invMultiSalesHeader sh
join invMultiSalesDetails sd on sh.CompanyID=sd.CompanyID and sh.PeriodID=sd.PeriodID and sh.VtypeID=sd.VtypeID and sh.No=sd.No
join #Customer c on sd.CustomerID=c.ID
where (sh.CompanyID=@CompanyID or @CompanyID=0) and sh.Date between @FromDate and @ToDate
group by c.Name


declare @Line varchar(25)
set @Line=replicate('-',25) 

create table #Balance(Customer nvarchar(100),OB money,Qty float,Debit money,Credit money,CB money) 
insert #Balance
select Customer,sum(OB),sum(Qty),sum(Debit),sum(Credit),sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)) 
from #aTransaction
group by Customer

if (@Status=2)
 delete #Balance where CB<=0

--Final
select Customer,
convert(varchar,OB,4)OB,convert(varchar,Qty,4)Qty,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB 
from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line
union all
select null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Qty),4)Qty,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4)Credit,convert(varchar,sum(isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)),4)CB from #Balance
union all
select null,@Line,@Line,@Line,@Line,@Line

go

if object_id('spCustomersAgeing') is not null drop proc spCustomersAgeing

go

create proc spCustomersAgeing 
@CompanyId int=1,
@ToDate int,
@AccountID int=0,
@Type tinyint, --0 Summary,1 Detailed
@From int=null,
@To int=null,
@SalesmanID int=null,
@PropertyFilter nvarchar(max)=null,
@Status tinyint=null,
@CostCentreId int=0

as

  set nocount on
  set transaction isolation level read uncommitted

  create table #Due 
  (SNo int,
   ID numeric ,
   Date int null default 0,
   VtypeID int,
   No int,
   Description nvarchar(200),
   Amount money
  )

  declare @FinalDue table
  (ID numeric ,
   Date int null default 0,
   SNo int,
   Rsales float ,
   TotReceived float ,
   Balance float )


   create table #Account (ID int,Name nvarchar(100),UnderAccountID int,Phone varchar(100))
   insert #Account(Id,Name,UnderAccountId) 
   select a.ID,a.name,a.ID from aAccount a join aSubGroupSettings sg on a.AccountSubGroupID=sg.SundryDebtors where	a.ID=@AccountID

   --Drilling for Under Accounts,
	--while @Type in(1,2) and @@rowcount>0
		insert #Account(Id,Name,UnderAccountId) 
		select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
		join #Account a2 on a1.UnderAccountID=a2.ID 
		left join #Account a3 on a1.ID=a3.ID
		where a3.ID is null
   
	
	if @SalesmanID>0
		delete a from #Account a join invCustomer c on a.ID=c.AccountID where c.SalesmanID<>@SalesmanID or c.SalesmanID is null
 
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
		delete t1 from #Account t1 
		left outer join @T1 t2 on t1.ID = t2.Id 
		where t2.Id is null
	  end
	end 


	--Active
	if @Status in (0,1)
	Begin
		if object_id('invCustomer') is not null
		Begin
			delete c from #Account c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
		end
	End
	

  --Phone
  update a set a.Phone=isnull(nullif(c.Phone,''),c.MobileNo) from #Account a join invCustomer c on a.ID=c.AccountID

  
  /*Amount*/
  insert #Due(SNo,ID,Date,VTypeID,No,Description,Amount) 
  select row_number()over(order by Date,No)SNo, DebtorID,Date,d.VoucherTypeID,isnull(No,0),d.Description,sum(Amount) from aTransaction d 
  join #Account a on a.ID=d.DebtorID 
  where (CompanyID=@CompanyId or @CompanyId=0)
  and (date <= @ToDate or Date is null) 
  and (CostCentreId=@CostCentreId or @CostCentreId=0)
  group by DebtorID,PeriodID,date,d.VoucherTypeID,d.No,d.Description

  
  insert @FinalDue (ID,Date,SNo,RSales) 
  select d.ID,dd.date,dd.SNo,sum(d.Amount) from #Due d
  join (select date,SNo,ID from #Due)dd
  on d.ID = dd.ID and d.SNo <= dd.SNo
  group by d.ID,dd.SNo,dd.date

  --Receipts
  declare @aTransaction table(VoucherTypeID int,CNo varchar(50),DebtorId int,CreditorId int,AccountId int,Date int,CompanyId int,Amount float)
  insert @aTransaction
  select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
  from aTransaction d join #Account a on a.id=d.CreditorID 
  where (date <=@ToDate or Date is null) 
  and (CompanyId=@CompanyId or @CompanyId=0)
  and (CostCentreId=@CostCentreId or @CostCentreId=0)

  

	if @Type=3 --W/O PDC
	Begin
		declare @CQR int,@CQP int,@CQC int,@BR int,@BP int
		select @CQR=ChequeReceipt,@CQP=ChequePayment,@CQC=ChequeClearing,@BR=BillwiseReceipt,@BP=BillwisePayment from aVoucherTypeSettings

		delete @aTransaction where VoucherTypeID in(@CQR,@CQP,@BR,@BP) and CNo is not null

		--To Insert Cleared
		insert @aTransaction
		select VoucherTypeID,CNo,DebtorId,CreditorId,AccountId,Date,CompanyId,Amount
		from aTransaction d join #Account a on a.id=d.AccountID 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		--To Insert Bounced
		insert @aTransaction
		select VoucherTypeID,CNo,CreditorId,DebtorId,AccountId,Date,CompanyId,Amount
		from aTransaction d 
		join #Account a on a.id=d.DebtorId 
		where (date <=@ToDate or Date is null) 
		and (CompanyId=@CompanyId or @CompanyId=0)
		and (CostCentreId=@CostCentreId or @CostCentreId=0)
		and VoucherTypeID=@CQC

		declare @PDCP int,@PDCR int
		select @PDCP=PDCPayable,@PDCR=PDCReceivable from aAccountSettings where CompanyID=@CompanyId
	
		update @aTransaction set DebtorID=AccountID,AccountID=null where (DebtorID=@PDCP or DebtorID=@PDCR)
		update @aTransaction set CreditorID=AccountID,AccountID=null where (CreditorID=@PDCP or CreditorID=@PDCR) and DebtorID<>AccountID
		
		
	End

  update r set r.totreceived = d.Amount from @FinalDue r join
  (select CreditorID,sum(Amount)Amount from @aTransaction group by CreditorID) d on d.CreditorID = r.ID

  delete from @FinalDue where round(RSales,1) <= round(isnull(TotReceived,0),1)

  delete d from #Due d left join @FinalDue f on d.ID=f.ID and d.SNo=f.SNo where f.SNo is null
  
  if not exists(select * from @FinalDue where RSales>isnull(TotReceived,0)) delete #Due

  update @FinalDue set Balance = RSales - isnull(TotReceived,0)

  declare @MinNo table(ID int,SNo int)
  insert @MinNo select ID,min(SNo) from @FinalDue group by ID

  delete d from #Due d join @MinNo m on d.ID = m.ID and d.SNo < m.SNo
  update d set d.Amount = f.balance from #Due d join @MinNo m on d.ID = m.ID and m.SNo = d.SNo join @FinalDue f on f.ID = m.ID and m.SNo = f.SNo
  ---------------

  --For calculating age, no future date need to consider
  if @ToDate>convert(varchar,current_timestamp,112) 
	  set @ToDate=convert(varchar,current_timestamp,112)


  --Filtering days
  if @From is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<@From 

  if @To is not null
	delete #Due where datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))>@To
  ----
  
  
  declare @Line varchar(13)
  set @Line=REPLICATE('_',13)

  declare @AI int
  select @AI=AgeInterval from aOption
  
  declare @1C varchar(max)
  select @1C=cast(@AI+1 as varchar)+'-'+cast(2*@AI as varchar)

  declare @2C varchar(max)
  select @2C=cast(2*@AI+1 as varchar)+'-'+cast(3*@AI as varchar)

  declare @3C varchar(max)
  select @3C=cast(3*@AI+1 as varchar)+'-'+cast(4*@AI as varchar)

  declare @4C varchar(max)
  select @4C=cast(4*@AI+1 as varchar)+'-'
  
  declare @DecimalFormat int
  select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption	

  if @Type in(1,2,3)
  Begin	
	
	--Balance
	declare @DueBal table(Ord int,ID int,Date int null default 0,VtypeID int,No int,Description nvarchar(200),Amount money,Balance money)
	
	insert @DueBal
    select row_number() over (partition by ID order by ID,Date),ID,Date,VtypeID,No,Description,Amount,null from #Due
	
	
	;with b as
	(select b.Ord,b.id,sum(s.Amount) Balance from @DueBal b join @DueBal s on s.id=b.id and s.Ord<=b.Ord group by b.Ord,b.id)

	update s set s.Balance=b.Balance from @DueBal s join b on b.id=s.id and s.Ord=b.Ord
	---------------------
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)

	Begin
	 		
		create table #FBal(Ord int,ID int,LedgerAccount nvarchar(100),Date int,VtypeID int,No int,Description nvarchar(200),Amount varchar(50),Age varchar(25),Balance varchar(50),Name nvarchar(100),Days int)
		 
		insert #FBal(Ord,ID,Date,VtypeID,No,Description,Amount,Age,Balance)
		select Ord,ID,Date,VtypeID,No,Description,
		convert(varchar,cast(Amount as money),4),
		datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)),
		convert(varchar,cast(Balance as money),4) from @DueBal

		
		insert #FBal(Ord,ID,Amount,Balance)
		select max(Ord)+1,ID,@Line,@Line from @DueBal group by ID 

		insert #FBal(Ord,ID,Amount)
		select max(Ord)+2,ID,convert(varchar,cast(sum(Amount) as money),4) from @DueBal group by ID 

		declare @AL int
		select @AL=max(len(Name)) from #Account

		declare @DL int
		select @DL=max(len(Description)) from #FBal

		insert #FBal(LedgerAccount,Ord,ID,Description,Age,Amount,Balance)
		select REPLICATE('_',@AL),max(Ord)+3,ID,REPLICATE('_',@DL),REPLICATE('_',5),@Line,@Line from @DueBal group by ID 

		declare @Address table(ID int,Address nvarchar(100),Ord int)
		insert @Address select ID,c.Name,1 from invCustomer c join #Account a on c.AccountID=a.ID
		insert @Address select ID,c.Address1,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address1)>0 group by ID,c.Address1 
		insert @Address select ID,c.Address2,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address2)>0 group by ID,c.Address2 
		insert @Address select ID,c.Address3,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Address3)>0 group by ID,c.Address3 
		insert @Address select ID,c.Place,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Place)>0 group by ID,c.Place
		insert @Address select ID,c.Phone,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.Phone)>0 group by ID,c.Phone
		insert @Address select ID,c.MobileNo,max(Ord)+1 from invCustomer c join @Address a on c.AccountID=a.ID where len(c.MobileNo)>0 group by ID,c.MobileNo

		update f set f.LedgerAccount=c.Address from #FBal f join @Address c on f.ID=c.ID and f.Ord=c.Ord where LedgerAccount is null
		
		-- Just for Ordering by Name
		update f set f.Name=a.Name from #Account a join #FBal f on f.ID=a.ID
		
		if @Type in(1,3)
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,Age,Amount,Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
		else
		Begin
			update #FBal set Days=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))
			exec('
			select LedgerAccount,
			cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,Amount,
			case when Days <='+@AI+' then Amount end[ 0-'+@AI+'] ,
			case when Days between '+@AI+'+1 and 2*'+@AI+' then Amount end[ '+@1C+'],
			case when Days between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end[ '+@2C+'],
			case when Days between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end[ '+@3C+'],
			case when Days >4*'+@AI+' or Date is null then Amount end[ '+@4C+'],
			Balance from #FBal d 
			left join aVoucherType v on d.VTypeID=v.ID
			Order by d.Name,Ord
			')
		End
	End
	Else
	Begin
		if @Type in(1,3)
		Begin
			select p.Id PeriodId,cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,convert(varchar,cast(d.Amount as money),@DecimalFormat) Amount,datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))Age,convert(varchar,cast(d.Balance as money),@DecimalFormat)Balance from @DueBal d
			join aPeriod p on d.Date between p.[From] and p.[To]
			left join aVoucherType v on d.VTypeID=v.ID
			union all
			select null,null,null,null,null,null,@Line,null,@Line
			union all
			select null,null,null,null,null,null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat),null,convert(varchar,cast(sum(Amount) as money),@DecimalFormat) from @DueBal
			union all
			select null,null,null,null,null,null,@Line,null,@Line
		End
		Else
		Begin	
			;with a as
			(select cast(cast(d.Date as varchar)as smalldatetime)Date,v.ID VoucherTypeID,v.Name VType,nullif(d.No,0)No,d.Description,
			 d.Amount Amount,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))<31 then Amount end [ 0-30] ,
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 31 and 45 then Amount end [ 31-45],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 46 and 60 then Amount end [ 46-60],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) between 61 and 90 then Amount end [ 61-90],
			 case when datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime)) > 90 or Date is null then Amount end [ 90-],
			 d.Balance from @DueBal d 
			 left join aVoucherType v on d.VTypeID=v.ID
			 )

			 select Date,VoucherTypeID,VType,No,Description,convert(varchar,Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-],convert(varchar,Balance,@DecimalFormat)Balance from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 union all
			 select null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat),convert(varchar,sum([ 0-30]),@DecimalFormat),convert(varchar,sum([ 31-45]),@DecimalFormat),convert(varchar,sum([ 46-60]),@DecimalFormat),convert(varchar,sum([ 61-90]),@DecimalFormat),convert(varchar,sum([ 90-]),@DecimalFormat),null from a
			 union all
			 select null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,null
			 
		End
	End
  End
  Else
  Begin
	  update #Due set Date=datediff(day,cast(cast(date as varchar) as smalldatetime),cast(cast(@ToDate as varchar) as smalldatetime))--,Amount=convert(varchar,Amount,@DecimalFormat)
	  
	  exec
	  ('
	  ;with a as	
	  (select a.Name Account,a.Phone,d.* from 
	  (select ID,
	  sum(case when Date <='+@AI+' then Amount end)[ 0-'+@AI+'] ,
	  sum(case when Date between '+@AI+'+1 and 2*'+@AI+' then Amount end)[ '+@1C+'],
	  sum(case when Date between 2*'+@AI+'+1 and 3*'+@AI+' then Amount end)[ '+@2C+'],
	  sum(case when Date between 3*'+@AI+'+1 and 4*'+@AI+' then Amount end)[ '+@3C+'],
	  sum(case when Date >4*'+@AI+' or Date is null then Amount end)[ '+@4C+'],
	  sum(Amount)Total
	  from #Due group by ID)d
	  join #Account a on a.ID = d.ID)

	  select * from
	  (select null Ord,ID,Account,Phone,convert(varchar,[ 0-'+@AI+'],'+@DecimalFormat+')[ 0-'+@AI+'],convert(varchar,[ '+@1C+'],'+@DecimalFormat+')[ '+@1C+'],convert(varchar,[ '+@2C+'],'+@DecimalFormat+')[ '+@2C+'],convert(varchar,[ '+@3C+'],'+@DecimalFormat+')[ '+@3C+'],convert(varchar,[ '+@4C+'],'+@DecimalFormat+')[ '+@4C+'],convert(varchar,Total,'+@DecimalFormat+')Total from a
	  union all
	  select 1,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  union all
	  select 2,null,null,null,convert(varchar,sum([ 0-'+@AI+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@1C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@2C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@3C+']),'+@DecimalFormat+'),convert(varchar,sum([ '+@4C+']),'+@DecimalFormat+'),convert(varchar,sum(Total),'+@DecimalFormat+') from a
	  union all
	  select 3,null,null,null,'''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+''','''+@Line+'''
	  )b order by Ord,Account')
  End  

  GO

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
		Order by Ord,Date,Debit Desc,VoucherTypeId desc,No
End

go

if object_id('spGetCustomers') is not null drop proc spGetCustomers

go

create proc spGetCustomers
@Date int,
@Status tinyint=null,
@PropertyFilter nvarchar(max)=null,
@CompanyID int,
@ModuleID tinyint=null,
@UserID int=null,
@SalesManID int=null

as

set nocount on
set xact_abort on

create table #Customer (ID int not null primary key,Code nvarchar(50),Name nvarchar(100),Phone nvarchar(200),Place nvarchar(100),FileNo varchar(50),UnderAccountID int,Balance float)


insert #Customer(ID,Code,Name,UnderAccountID)
select ID,Code,Name,UnderAccountID from aAccount where AccountSubGroupID=(select SundryDebtors from aSubGroupSettings)


if object_id('invUserCompany') is not null
Begin
	--Delete other company Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		left join aCompany co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null


	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCompany uc on c.CompanyID=uc.CompanyID 
		join invUser u on uc.UserId=u.Id
		left join aCompany co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

if object_id('invUserCostCentre') is not null
Begin
	--Delete other CC Customers for Inventory
	if @ModuleID=1 and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		left join invSalesman s on c.SalesManId=s.Id
		--join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUserCostCentre uc on COALESCE(c.CostCentreId,s.CostCentreId,0)=isnull(uc.CostCentreId,0)
		left join invCostCentre co on a.ID=co.AccountID
		where uc.UserID=@UserID and uc.Customer=0 and co.ID is null
		

	--Delete other company Customers for AMS
	if @ModuleID is null and @UserID>0
		delete a from #Customer a
		join invCustomer c on a.ID=c.AccountID
		join invUserCostCentre uc on isnull(c.CostCentreId,0)=isnull(uc.CostCentreId,0) 
		join invUser u on uc.UserId=u.Id
		left join invCostCentre co on a.ID=co.AccountID
		where u.amsUserID=@UserID and uc.Customer=0 and co.ID is null 

End
-----------------------------------------------------------------

--Default Customer
if object_id('invOption') is not null
Begin
	declare @DefaultCustomer int
	select @DefaultCustomer=DefaultCustomer from invOption where CompanyId=@CompanyId
	if not exists(select 1 from #Customer where Id=@DefaultCustomer)
		insert #Customer(ID,Code,Name,UnderAccountID)
		select Id,Code,Name,UnderAccountID from aAccount where Id=@DefaultCustomer
End



if LEN(@PropertyFilter) > 0
begin
	declare @T1 table (Id int)

	if OBJECT_ID('vw_CustomerProperty') is not null
	begin
		insert @T1 exec
		('
		select t1.AccountID from invAccountPropertyDetails t1
		join vw_CustomerProperty t2 on t1.AccountID = t2.AccountId 
		where ' + @PropertyFilter + '
		')
	end

	if OBJECT_ID('vw_AccountProperty') is not null
	begin
		insert @T1 exec
		('
		select t1.AccountID from invAccountPropertyDetails t1
		join vw_AccountProperty t2 on t1.AccountID = t2.Id 
		where ' + @PropertyFilter + '
		')
	end

	delete t1 from #Customer t1 
    left outer join @T1 t2 on t1.ID = t2.Id 
    where t2.Id is null and t1.UnderAccountID is not null
  
end 



--Active
if @Status in (0,1)
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(Inactive,0)<>@Status
	end
End

--Active + Balance<>0
if @Status=5
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where Inactive=1
	end
End


if object_id('invCustomer') is not null
Begin
	--Company Customers
	insert #Customer(ID,Code,Name,UnderAccountID)
	select t2.[Id],t2.[Code],t2.[Name],t2.UnderAccountId from invCustomer t1
	join aCompany c on t1.AccountId=c.AccountId
	join aAccount t2 on t1.AccountId = t2.Id
	left join #Customer cu on t1.AccountId=cu.Id where cu.Id is null
End


if @SalesManID>0
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID where isnull(SalesManID,0)<>@SalesManID
	end
End


--Balance
create table #Balance
(
 Level nvarchar(100),
 AccountID int,
 Balance float
)

insert #Balance(Level,AccountID) select c1.ID,c1.ID from #Customer c1 left join #Customer c2 on c1.UnderAccountID=c2.ID where (c1.UnderAccountID is null or c1.ID=c1.UnderAccountID or c2.ID is null)

while @@rowcount>0
Begin
	insert #Balance(Level,AccountID)
	select b.Level +'*'+cast(a.ID as varchar),a.ID from #Balance b 
	join aAccount a on b.AccountID=a.UnderAccountID 
	where a.ID not in(select AccountID from #Balance)
End


;with b as	
(select AccountID,sum(Balance)Balance from 
(select v.DebtorID AccountID,Amount Balance from aTransaction v join #Balance b on v.DebtorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0
 union all
 select v.CreditorID,-Amount from aTransaction v join #Balance b on v.CreditorID=b.AccountID where CompanyID=@CompanyID or @CompanyID=0)b
 group by AccountID
 )

update b1 set b1.Balance=b2.Balance from #Balance b1 join b b2 on b1.AccountID=b2.AccountID



--Accounts
update c set c.Balance=b.Balance from #Customer c join #Balance b on c.ID=b.AccountID

select sum(Balance)Balance from #Customer where id not in(select underaccountid from #Customer where underaccountid is not null)

if exists(select top 1 1 from #Balance where level like '%*%')
Begin
	--Under Levels
	;with b as (select * from #Balance where Balance is not null)
	,lb as
	(select b1.level,sum(b2.balance)Balance from #Balance b1 join b b2 on b2.level+'*' like b1.level+'*%' group by b1.level)

	update c set c.Balance=l.Balance from #Balance b join #Customer c on b.accountid=c.id join lb l on b.Level=l.Level

End
--Balance---------------------------------------

--Place
if object_id('invCustomer') is not null
Begin
	update c set c.Place=i.Place,c.FileNo=i.FileNo,c.Phone=rtrim(ltrim(isnull(i.Phone,'')+'   '+isnull(i.MobileNo,''))) from #Customer c join invCustomer i on c.ID=i.AccountID
End

if @Status in(2,5)-- Balance<>0
	delete #Customer where Balance is null or round(Balance,2)=0


if @Status=3-- Balance>Credit Limit
Begin
	if object_id('invCustomer') is not null
	Begin
		delete c from #Customer c join invCustomer ic on c.ID=ic.AccountID and isnull(c.Balance,0)<=ic.CreditLimit
	end
End


if @Status=4-- Balance=0
	delete #Customer where Balance<>0

update #Customer set Name=replace(Name,'"','''')

if not exists(select 1 from #Customer where isnumeric(FileNo)=0 and FileNo is not null)
	select ID,cast(FileNo as int)FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer order by Name
else
	select ID,FileNo,Code,Name,Phone,Place,Balance,UnderAccountId from #Customer

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

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
select @BR=BillwiseReceipt,@CR=ChequeReceipt,@CC=ChequeClearing,@BKR=BankReceipt from aVoucherTypeSettings

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


if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(t.DDate as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date


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


insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,sum(tr.Amount) from aTransaction tr 
join @Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,-sum(tr.Amount) from aTransaction tr 
join @Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

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
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(OB)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@OptCompanyId

exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=@FromDate,@Date=@Date,@NP=@NP output

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount)
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(Period)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@OptCompanyId



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

if object_id('spAssets') is not null 
	drop proc spAssets

go

create proc spAssets
@CompanyID int,
@CostCentreId int=0,
@Date int,
@Level tinyint=0
as

set nocount on
set transaction isolation level read uncommitted

declare @OptCompanyId int
select @OptCompanyId=@CompanyId
if @OptCompanyId=0 select @OptCompanyId=min(Id) from aCompany

create table #Account (Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),ID int,Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,Level tinyint)

insert #Account
select t.Name,g.Name,s.Name,a.ID,a.Name,a.NameInOL,a.UnderAccountID,0 from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
join aAccountType t on g.AccountTypeID=t.ID
where g.AccountTypeID=1 and (a.UnderAccountID is null or a.ID=a.UnderAccountID)


--Drilling for Under Accounts
while @@rowcount>0
	insert #Account
	select a2.Type,a2.[Group],a2.SubGroup,a1.ID,a1.Name,a1.NameInOL,a1.UnderAccountID,a2.Level+1 from aAccount a1 
	join #Account a2 on a1.UnderAccountID=a2.ID 
	left join #Account a3 on a1.ID=a3.ID
	where a3.ID is null


declare @Assets table(Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),AccountID int,Account nvarchar(100),NameInOL nvarchar(100),Amount float,Level tinyint)

insert @Assets(Type,[Group],SubGroup,AccountID,Account,NameInOL,Level,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level,sum(tr.Amount) from aTransaction tr 
join #Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level


insert @Assets(Type,[Group],SubGroup,AccountID,Account,NameInOL,Level,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level,-sum(tr.Amount) from aTransaction tr 
join #Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level

--Climbing for Levels
while exists(select top 1 1 from @Assets where Level>@Level)
Begin
	update t set t.AccountID=a.UnderAccountID,t.Account=u.Name,t.NameInOL=u.NameInOL,t.Level=t.Level-1 from @Assets t join #Account a on t.AccountID=a.ID join #Account u on a.UnderAccountID=u.ID where a.UnderAccountID is not null and t.Level>@Level
End


--Closing Stock
if exists(select 1 from sysobjects where name='invOption')
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin  
		declare @Stock float
		if (@CompanyID=0)
			Begin
				declare @CId int
				declare @CStock float
				set @CId=0
				while exists(select Id from aCompany where Id>@CID)
				Begin
					select top 1 @CId=Id from aCompany where Id>@CId
					set @CStock=null
					exec spStock @CompanyID=@CId,@CostCentreId=@CostCentreId,@ToDate=@Date,@Type=@CStock output
					set @Stock=isnull(@Stock,0)+isnull(@CStock,0)
				End
			End
		Else
			exec spStock @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@ToDate=@Date,@Type=@Stock output

		if exists(select 1 from invOption where StockCalculation=2)--SerialNowise
		Begin
			declare @Type float
			set @Type=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=@Date,@Type=@Type output
			set @Stock=isnull(@Stock,0)+isnull(@Type,0)
		End	
		
		declare @SIH int
		select top 1 @SIH=StockInHand from aAccountSettings where CompanyId=@OptCompanyId order by CompanyId
		
		insert @Assets(Type,[Group],SubGroup,AccountId,Account,Amount)
		select a.Type,a.[Group],a.SubGroup,a.Id,a.Name,@Stock from #Account a where a.Id=@SIH
	End
End

if exists(select 1 from sysobjects where name='prPhyStockValue')  
begin
    declare @Stock2 float  
    exec prPhyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock2 output  
   
    insert @Assets(Type,[Group],SubGroup,Account,Amount)
	select t.Name,g.Name,s.Name,'STOCK IN HAND',@Stock2 from aAccountType t 
	join aAccountGroup g on g.AccountTypeID=t.ID
	join aAccountSubGroup s on s.AccountGroupID=g.ID
	join aSubGroupSettings ss on ss.CurrentAsset=s.ID
end

if exists(select 1 from sysobjects where name='prWpyStockValue')  
begin
   declare @Stock3 float  
   exec prWpyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock3 output  
   
    insert @Assets(Type,[Group],SubGroup,Account,Amount)
	select t.Name,g.Name,s.Name,'STOCK IN HAND',@Stock3 from aAccountType t 
	join aAccountGroup g on g.AccountTypeID=t.ID
	join aAccountSubGroup s on s.AccountGroupID=g.ID
	join aSubGroupSettings ss on ss.CurrentAsset=s.ID
end

select Type,[Group],SubGroup,Account,NameInOL,sum(Amount)Amount from @Assets group by Type,[Group],SubGroup,Account,NameInOL
having round(sum(Amount),3)<>0

go

if object_id('spTrialBalanceGridPeriodwise') is not null drop proc spTrialBalanceGridPeriodwise

go

create proc spTrialBalanceGridPeriodwise
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

declare @TB table(AccountID int,OB money,Debit money,Credit money,CB money)

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
			select @Profit=Profit from aAccountSettings where CompanyID=@CompanyID
			insert @TB(AccountID,OB,CB) values (@Profit,-@NP,-@NP)
		End


		if isnull(@Stock,0)<>0 or isnull(@SM,0)<>0
		Begin
			declare @OS int
			declare @OBE int
			select @OS=OpeningStock,@OBE=OpeningBalanceEquity from aAccountSettings where (CompanyID=@CompanyID or @CompanyId=0)
			if @OS>0 and @OBE>0
			Begin
				insert @TB(AccountID,CB) values (@OS,@Stock)
				insert @TB(AccountID,CB) values (@OBE,@SM)
				insert @TB(AccountID,CB) values (@OBE,-@Stock)
			End
		End
	End
End
------------------


--OB
update @TB set OB=CB-isnull(Debit,0)+isnull(Credit,0) where OB is null

--select * from @TB where AccountId=69 return

--Final Data
;with tb as
(select ID,SGCode,a.Name Account,sum(OB)OB,sum(Debit)Debit,sum(Credit)Credit,sum(CB)CB from @TB t
 join @Account a on a.ID=t.AccountID
 group by a.ID,a.SGCode,a.SGName,a.Code,a.Name,a.NameInOL
 having round(sum(OB),2)<>0 or round(sum(Debit),2)<>0 or round(sum(Credit),2)<>0 or round(sum(CB),2)<>0
 )

 --select * from tb where isnull(OB,0)+isnull(Debit,0)-isnull(Credit,0)<>isnull(CB,0)

select AccountId,Account,OB,Debit,Credit,CB
from
(select 0 Ord,ID AccountId,Account,convert(varchar,OB,4)OB,convert(varchar,Debit,4)Debit,convert(varchar,Credit,4)Credit,convert(varchar,CB,4)CB from tb 
union all
select 1 Ord,null,null,replicate('-',30),replicate('-',30),replicate('-',30),replicate('-',30)
union all
select 2 Ord,null,null,convert(varchar,sum(OB),4)OB,convert(varchar,sum(Debit),4)Debit,convert(varchar,sum(Credit),4),convert(varchar,sum(CB),4)CB from tb 
union all
select 3 Ord,null,null,replicate('-',30),replicate('-',30),replicate('-',30),replicate('-',30)
)
a order by Ord,Account


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

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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
select @BR=BillwiseReceipt,@CR=ChequeReceipt,@CC=ChequeClearing,@BKR=BankReceipt from aVoucherTypeSettings

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


if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(t.DDate as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date


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


insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,sum(tr.Amount) from aTransaction tr 
join @Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,-sum(tr.Amount) from aTransaction tr 
join @Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL

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
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(OB)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@OptCompanyId

exec spGetNetProfit @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@FromDate=@FromDate,@Date=@Date,@NP=@NP output

insert @Liabilities(Type,[Group],SubGroup,AccountID,Account,NameInOL,Amount)
select top 1 a.Type,a.[Group],a.SubGroup,a.ID,a.Name+'(Period)',a.NameInOL,@NP from aAccountSettings s
join @Account a on s.Profit=a.ID 
where s.CompanyId=@OptCompanyId



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

if object_id('spAssets') is not null 
	drop proc spAssets

go

create proc spAssets
@CompanyID int,
@CostCentreId int=0,
@Date int,
@Level tinyint=0
as

set nocount on
set transaction isolation level read uncommitted

declare @OptCompanyId int
select @OptCompanyId=@CompanyId
if @OptCompanyId=0 select @OptCompanyId=min(Id) from aCompany

create table #Account (Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),ID int,Name nvarchar(100),NameInOL nvarchar(100),UnderAccountID int,Level tinyint)

insert #Account
select t.Name,g.Name,s.Name,a.ID,a.Name,a.NameInOL,a.UnderAccountID,0 from aAccount a
join aAccountSubGroup s on a.AccountSubGroupID=s.ID
join aAccountGroup g on s.AccountGroupID=g.ID
join aAccountType t on g.AccountTypeID=t.ID
where g.AccountTypeID=1 and (a.UnderAccountID is null or a.ID=a.UnderAccountID)


--Drilling for Under Accounts
while @@rowcount>0
	insert #Account
	select a2.Type,a2.[Group],a2.SubGroup,a1.ID,a1.Name,a1.NameInOL,a1.UnderAccountID,a2.Level+1 from aAccount a1 
	join #Account a2 on a1.UnderAccountID=a2.ID 
	left join #Account a3 on a1.ID=a3.ID
	where a3.ID is null


declare @Assets table(Type nvarchar(50),[Group] nvarchar(50),SubGroup nvarchar(50),AccountID int,Account nvarchar(100),NameInOL nvarchar(100),Amount float,Level tinyint)

insert @Assets(Type,[Group],SubGroup,AccountID,Account,NameInOL,Level,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level,sum(tr.Amount) from aTransaction tr 
join #Account a on tr.DebtorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level


insert @Assets(Type,[Group],SubGroup,AccountID,Account,NameInOL,Level,Amount) 
select a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level,-sum(tr.Amount) from aTransaction tr 
join #Account a on tr.CreditorID=a.ID 
where (tr.Date<=@Date or tr.Date is null) 
and (@CompanyID=0 or tr.CompanyID=@CompanyID)
and (@CostCentreId=0 or tr.CostCentreId=@CostCentreId)
group by a.Type,a.[Group],a.SubGroup,a.ID,a.Name,a.NameInOL,a.Level

--Climbing for Levels
while exists(select top 1 1 from @Assets where Level>@Level)
Begin
	update t set t.AccountID=a.UnderAccountID,t.Account=u.Name,t.NameInOL=u.NameInOL,t.Level=t.Level-1 from @Assets t join #Account a on t.AccountID=a.ID join #Account u on a.UnderAccountID=u.ID where a.UnderAccountID is not null and t.Level>@Level
End


--Closing Stock
if exists(select 1 from sysobjects where name='invOption')
Begin
	if not exists(select 1 from invOption where CostOfGoodsSoldAccountId>0 and CompanyId=@OptCompanyId)
	Begin  
		declare @Stock float
		if (@CompanyID=0)
			Begin
				declare @CId int
				declare @CStock float
				set @CId=0
				while exists(select Id from aCompany where Id>@CID)
				Begin
					select top 1 @CId=Id from aCompany where Id>@CId
					set @CStock=null
					exec spStock @CompanyID=@CId,@CostCentreId=@CostCentreId,@ToDate=@Date,@Type=@CStock output
					set @Stock=isnull(@Stock,0)+isnull(@CStock,0)
				End
			End
		Else
			exec spStock @CompanyID=@CompanyID,@CostCentreId=@CostCentreId,@ToDate=@Date,@Type=@Stock output

		if exists(select 1 from invOption where StockCalculation=2)--SerialNowise
		Begin
			declare @Type float
			set @Type=0
			exec prIMIStockReport @CompanyID=@CompanyID,@Date=@Date,@Type=@Type output
			set @Stock=isnull(@Stock,0)+isnull(@Type,0)
		End	
		
		declare @SIH int
		select top 1 @SIH=StockInHand from aAccountSettings where CompanyId=@OptCompanyId order by CompanyId
		
		insert @Assets(Type,[Group],SubGroup,AccountId,Account,Amount)
		select a.Type,a.[Group],a.SubGroup,a.Id,a.Name,@Stock from #Account a where a.Id=@SIH
	End
End

if exists(select 1 from sysobjects where name='prPhyStockValue')  
begin
    declare @Stock2 float  
    exec prPhyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock2 output  
   
    insert @Assets(Type,[Group],SubGroup,Account,Amount)
	select t.Name,g.Name,s.Name,'STOCK IN HAND',@Stock2 from aAccountType t 
	join aAccountGroup g on g.AccountTypeID=t.ID
	join aAccountSubGroup s on s.AccountGroupID=g.ID
	join aSubGroupSettings ss on ss.CurrentAsset=s.ID
end

if exists(select 1 from sysobjects where name='prWpyStockValue')  
begin
   declare @Stock3 float  
   exec prWpyStockValue @CompanyID=@CompanyID,@Date=@Date,@Stock=@Stock3 output  
   
    insert @Assets(Type,[Group],SubGroup,Account,Amount)
	select t.Name,g.Name,s.Name,'STOCK IN HAND',@Stock3 from aAccountType t 
	join aAccountGroup g on g.AccountTypeID=t.ID
	join aAccountSubGroup s on s.AccountGroupID=g.ID
	join aSubGroupSettings ss on ss.CurrentAsset=s.ID
end

select Type,[Group],SubGroup,Account,NameInOL,sum(Amount)Amount from @Assets group by Type,[Group],SubGroup,Account,NameInOL
having round(sum(Amount),3)<>0

go

if exists(select * from sysIndexes where name='IndaMultiJournalDtl') drop Index aMultiJournalDtl.IndaMultiJournalDtl
go
Create unique clustered Index IndaMultiJournalDtl on aMultiJournalDtl(CompanyId,PeriodId,No,DebtorId,CreditorId,SNo) with fillfactor=90

go

alter proc spGetCustomerCentreReportTypes
as

select * from aCustomerCentreReportTypes where Checked=1 order by Id


go

if object_id('spGetCustomerOutstandingBills') is not null drop proc spGetCustomerOutstandingBills

go
create proc spGetCustomerOutstandingBills
@CompanyID int,
@PeriodID int=0,
@CustomerID int=0,
@No int=0,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999,
@PropertyFilter nvarchar(max)=null,
@CostCentreId int=0

as

set transaction isolation level read uncommitted

declare @Customer table(ID int,Name nvarchar(100),UnderAccountID int)

if @CustomerID=0
	insert @Customer(ID)
	select CustomerID from aBillwiseReceiptHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
else
	insert @Customer 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@CustomerID


while @Type in(1,2,3,4) and @@rowcount>0
	insert @Customer 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Customer a2 on a1.UnderAccountID=a2.ID 
	left join @Customer a3 on a1.ID=a3.ID
	where a3.ID is null


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
	delete t1 from @Customer t1 
	left outer join @T1 t2 on t1.ID = t2.Id 
	where t2.Id is null
	end
end 


declare @VoucherTypeID int
select @VoucherTypeID=BillwiseReceipt from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

create table #aTransaction(CHK bit,CustomerID int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),BAmount float,Amount float,Paid float,Discount float)


insert #aTransaction(CHK,CustomerID,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,Amount)
select cast(0 as bit),c.ID,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,case when DebtorID=c.ID then CreditorID else DebtorID end,Description,Amount,case when DebtorID=c.ID then 1 else -1 end*Amount from aTransaction t
join @Customer c on (t.DebtorID=c.ID or t.CreditorID=c.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate
and (@CostCentreId=0 or t.CostCentreId=@CostCentreId)

--Advance
insert #aTransaction(CHK,CustomerID,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,Amount)
select cast(0 as bit),c.ID,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,DebtorID,'Advance',-Advance from aBillwiseReceiptHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Customer c on b1.CustomerID=c.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate
and (@CostCentreId=0 or b1.CostCentreId=@CostCentreId)


;with p as
(select CustomerId,EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount from aBillwiseReceiptDtl d
 join aBillwiseReceiptHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)c on d.CompanyID=c.CompanyID and d.PeriodID=c.PeriodID and d.No=c.No
 join @Customer cu on h.CustomerID=cu.ID
 where d.CompanyID=@CompanyID and c.No is null group by CustomerId,EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0) from #aTransaction a join p b on a.CustomerId=b.CustomerId and isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from #aTransaction a join aBillwiseReceiptDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No


declare @DecimalFormat int
select @DecimalFormat=case when DecimalPlaces>2 then 2 else 4 end from aOption


if @Type in(1,2,3,4)
Begin
	
	declare @Date smalldatetime
	set @Date=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,CustomerID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Month int,Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money,Debit money,Credit money)
	
	if exists(select top 1 1 from aAccount where UnderAccountID=@CustomerID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			
			insert @T(Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by CustomerID order by CustomerID)Ord,
			CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			
			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else if @Type=2
		Begin
			insert @T(Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by CustomerID order by CustomerID,Date)Ord,CustomerID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from #aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)Age,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,null,@Line
			
		End
		Else if @Type=3
		Begin
			insert @T(CustomerID,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-],Amount)			
			select CustomerID,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-],
			Amount  
			from #aTransaction where round(Amount,4)<>0

			select c.Name Customer,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-],convert(varchar,sum(Amount),4)Total from @T t
			join @Customer c on t.CustomerID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			group by c.Name
			union all
			select null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-],convert(varchar,sum(Amount),4)Total from @T t
			union all
			select null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else if @Type=4 --Monthwise
		Begin
			insert @T(Ord,CustomerId,PeriodID,Month,Debit,Credit,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by CustomerID order by CustomerID,Month)Ord,* from
			(select CustomerId,PeriodID,Date/100 Month,sum(case when Amount>0 then Amount end)Debit,-sum(case when Amount<0 then Amount end)Credit,sum(Amount)Amount,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end) [ 0-30] ,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end) [ 31-45],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end) [ 46-60],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end) [ 61-90],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end) [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			group by CustomerId,PeriodID,Date/100
			)t

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,Left(Datename(Month,cast(Month*100+1 as varchar)),3)+' - '+substring(cast(Month as varchar),3,2) Month,
			cast(t.Debit as varchar)Debit,
			cast(t.Credit as varchar)Credit,
			cast(t.Amount as varchar)Amount,
			cast([ 0-30] as varchar)[ 0-30],
			cast([ 31-45] as varchar)[ 31-45],
			cast([ 46-60] as varchar)[ 46-60],
			cast([ 61-90] as varchar)[ 61-90],
			cast([ 90-] as varchar)[ 90-]	from @T t
			join @Customer c on t.CustomerID=c.ID
			union all
			select null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,cast(sum(Debit) as varchar),cast(sum(Credit) as varchar),cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
		End
			
	End
	Else
	Begin
		if @Type=1
		Begin
			
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			--order by Date
			
			select PeriodId,Date,VoucherTypeId,VType,No,SNo,Account,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-] from
			(select 0 Ord,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,@DecimalFormat)Amount,convert(varchar,[ 0-30],@DecimalFormat)[ 0-30],convert(varchar,[ 31-45],@DecimalFormat)[ 31-45],convert(varchar,[ 46-60],@DecimalFormat)[ 46-60],convert(varchar,[ 61-90],@DecimalFormat)[ 61-90],convert(varchar,[ 90-],@DecimalFormat)[ 90-] from @T t
			 join aAccount a on t.AccountID=a.ID
			 left join aVoucherType v on t.VoucherTypeID=v.ID
			 union all
			 select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			 union all
			 select 2,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat)Amount,convert(varchar,sum([ 0-30]),@DecimalFormat)[ 0-30],convert(varchar,sum([ 31-45]),@DecimalFormat)[ 31-45],convert(varchar,sum([ 46-60]),@DecimalFormat)[ 46-60],convert(varchar,sum([ 61-90]),@DecimalFormat)[ 61-90],convert(varchar,sum([ 90-]),@DecimalFormat)[ 90-] from @t
			 union all
			 select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			)a order by Ord,Date
		End
		Else if @Type=4 --Monthwise
		Begin
			insert @T(PeriodID,Month,Debit,Credit,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,Date/100,sum(case when Amount>0 then Amount end),-sum(case when Amount<0 then Amount end),sum(Amount),
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)<31 then Amount end) [ 0-30] ,
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 31 and 45 then Amount end) [ 31-45],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 46 and 60 then Amount end) [ 46-60],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) between 61 and 90 then Amount end) [ 61-90],
			sum(case when datediff(day,cast(cast(date as varchar) as smalldatetime),@Date) > 90 or Date is null then Amount end) [ 90-]   
			from #aTransaction where round(Amount,4)<>0
			group by PeriodID,Date/100
			
			select t.PeriodID,Left(Datename(Month,cast(Month*100+1 as varchar)),3)+' - '+substring(cast(Month as varchar),3,2) Month,
			cast(t.Debit as varchar)Debit,
			cast(t.Credit as varchar)Credit,
			cast(t.Amount as varchar)Amount,
			cast([ 0-30] as varchar)[ 0-30],
			cast([ 31-45] as varchar)[ 31-45],
			cast([ 46-60] as varchar)[ 46-60],
			cast([ 61-90] as varchar)[ 61-90],
			cast([ 90-] as varchar)[ 90-]	from @T t
			union all
			select null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,cast(sum(Debit) as varchar),cast(sum(Credit) as varchar),cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @t
			union all
			select null,null,@Line,@Line,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from #aTransaction 
			where round(Amount,4)<>0
			--order by Date
			
			select PeriodID,Date,VoucherTypeID,VType,No,SNo,Account,Description,Age,Amount from
			(
			select 0 Ord,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),@Date)Age,convert(varchar,t.Amount,@DecimalFormat)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select 1,null,null,null,null,null,null,null,null,null,@Line
			union all
			select 2,null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),@DecimalFormat)Amount from @T t
			union all
			select 3,null,null,null,null,null,null,null,null,null,@Line
			)a order by Ord,Date
		End
	End
End
Else
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.RefNo,t.SNo,a.Name Account,t.Description,t.BAmount,t.Amount,t.Paid,t.Discount,null Balance from #aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,4)<>0
	order by Date,No,SNo desc


go

if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
Begin
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(nullif(t.DDate,0) as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date
End

go

if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
Begin
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(nullif(case when t.DDate<2099 then t.DDate end,0) as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date
End

go

if object_id('spGetSalesCollection') is not null drop proc spGetSalesCollection

go

create proc spGetSalesCollection
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int=null,
@OB bit,
@Type tinyint=null

as

declare @SC table(LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,CostCentre nvarchar(50))

insert @SC(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@Type=@Type


if object_id('invSalesDetails') is not null
Begin
	declare @Sales table(LedgerAccountID int,LedgerAccount varchar(100),Date smalldatetime,CompanyID int,VType varchar(50),No int,Account varchar(100),Description varchar(300),Qty float,Debit float,Credit float)	
		
	declare @LedgerAccounts table(LedgerAccountID int)
	insert @LedgerAccounts 
	select distinct LedgerAccountID from @SC

	declare @DSC table(CompanyID int,PeriodID int,VoucherTypeID int,No int)
	insert @DSC select distinct CompanyID int,PeriodID int,VoucherTypeID,No from  @SC

	--Normal Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name + '   ' +cast(d.Rate as varchar),d.Qty,d.Total,case when h.PaymentMode=0 then d.Total end from invSalesDetails d 
	join invSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on d.ProductID=p.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Advance',h.Paid from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Paid<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate and h.PaymentMode=1


	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Discount',case when h.PaymentMode=0 then h.Discount end,h.Discount from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Discount<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Addition',h.Addition,case when h.PaymentMode=0 then h.Addition end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	declare @AdditionCaption varchar(100),@RoundOffCaption varchar(100)
	select @RoundOffCaption=SalesRoundOffCaption from invOption where CompanyID=@CompanyID

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@RoundOffCaption,h.RoundOff,case when h.PaymentMode=0 then h.RoundOff end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.RoundOff<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--Multi Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name,d.Qty,d.Gross,case when h.PaymentMode=0 then d.Gross end from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on h.ProductID=p.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@AdditionCaption,case when h.PaymentMode=0 then abs(d.Addition) end,abs(d.Addition) from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where d.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--;with v as(select distinct vtype from @Sales)
	--delete s from @SC s join v on s.VType=v.VType

	delete s1 from @SC s1 join @Sales s2 on s1.CompanyID=s2.CompanyID and s1.Date=s2.Date and s1.VType=s2.VType and s1.No=s2.No 

End


insert @SC(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
select LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit from @Sales

--Company
if @CompanyID=0
	update l set l.Company=c.Name from @SC l join aCompany c on l.CompanyID=c.ID

--Rep Updation
--------------
declare @CRVTypeID int
select @CRVTypeID=CashReceipt from aVoucherTypeSettings

update s set s.Description = isnull(s.Description,'')+rp.Name from @SC s 
join aCashReceiptHdr r on s.VoucherTypeID=@CRVTypeID and s.No=r.No 
join invRep1 rp on r.RepID=rp.ID
where r.CompanyID=@CompanyID and r.PeriodID=@PeriodID
-------------------------------------------

--Balance
declare @SCB table(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount varchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,Balance float,CostCentre nvarchar(50))

insert @SCB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Qty,Debit,Credit,AccountId,CostCentre)
select row_number() over (partition by LedgerAccountID order by LedgerAccountID,Date,VoucherTypeID desc,No),* from @sc


;with b as
(select b.Ord,b.LedgerAccountID,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from @SCB b join @SCB s on b.LedgerAccountID=s.LedgerAccountID and s.Ord<=b.Ord group by b.Ord,b.LedgerAccountID)

update s set s.Balance=b.Balance from @SCB s join b on s.LedgerAccountID=b.LedgerAccountID and s.Ord=b.Ord
-----------------


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
	select case when Ord=1 then LedgerAccount end LedgerAccount,Date,VType,No,Account,Description,Debit,Credit,Balance from @SCB
else
Begin
	declare @Line varchar(25)
	set @Line=REPLICATE('-',25)
	select Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,Qty,Debit,Credit,Balance
	from
	(select 0 Ord,Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,cast(Qty as varchar)Qty,convert(varchar,cast(Debit as money),4)Debit,convert(varchar,cast(Credit as money),4)Credit,convert(varchar,cast(Balance as money),4)Balance from @SCB
	union all
	select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	union all
	select 2,null,null,null,null,null,null,null,null,cast(sum(Qty) as varchar),convert(varchar,cast(sum(Debit) as money),4),convert(varchar,cast(sum(Credit) as money),4),null from @SCB
	union all
	select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	)a
	Order by Ord,Date,VoucherTypeId desc,No
End
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

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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


if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
Begin
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(nullif(t.DDate,0) as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date
End

go

if object_id('spGetVendorOutstandingBills') is not null drop proc spGetVendorOutstandingBills

go

create proc spGetVendorOutstandingBills
@CompanyID int,
@PeriodID int=0,
@VendorID int=0,
@No int=0,
@Date int=99999999,
@Type tinyint=0,
@FromDate int=19000101,
@ToDate int=99999999


as

set transaction isolation level read uncommitted

declare @Vendor table(ID int,Name nvarchar(100),UnderAccountID int)

if @VendorID=0
Begin
	select @VendorID=VendorID,@Date=Date from aBillwisePaymentHdr where CompanyID=@CompanyID and PeriodID=@PeriodID and No=@No
	insert @Vendor(ID) values(@VendorID)
End
else
	insert @Vendor 
	select a.ID,a.name,a.ID from aAccount a where a.ID=@VendorID

while @Type in(1,2) and @@rowcount>0
	insert @Vendor 
	select a1.ID,a1.Name,a1.UnderAccountID from aAccount a1 
	join @Vendor a2 on a1.UnderAccountID=a2.ID 
	left join @Vendor a3 on a1.ID=a3.ID
	where a3.ID is null


declare @VoucherTypeID int
select @VoucherTypeID=BillwisePayment from aVoucherTypeSettings

declare @OBDate int
select @OBDate=min([From])-1 from aPeriod where Id=@PeriodId or @PeriodId=0

declare @aTransaction table(CHK bit,VendorId int,PeriodID int,Date int,VoucherTypeID int,No int,RefNo varchar(50),SNo int,AccountID int,Description nvarchar(200),DDate int,Age int,BAmount float,BOD float,Amount float,Paid float,Discount float)

insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,AccountID,Description,BAmount,BOD,Amount)
select cast(0 as bit),v.Id,PeriodID,Date,VoucherTypeID,No,RefNo,SNo,
case when DebtorID=v.Id then CreditorID else DebtorID end,Description,Amount,
case when DebtorID=v.Id and Date<=@Date then -1 else 1 end*Amount,
case when DebtorID=v.Id then -1 else 1 end*Amount 
from aTransaction t
join @Vendor v on (t.DebtorID=v.ID or t.CreditorID=v.ID)
where CompanyID=@CompanyID 
and (VoucherTypeID is null or VoucherTypeID<>@VoucherTypeID)
and isnull(Date,@OBDate) between @FromDate and @ToDate

--Advance
insert @aTransaction(CHK,VendorId,PeriodID,Date,VoucherTypeID,No,RefNo,AccountID,Description,BOD,Amount)
select cast(0 as bit),v.Id,b1.PeriodID,Date,@VoucherTypeID,b1.No,RefNo,CreditorID,'Advance',case when Date<=@Date then -Advance end,-Advance from aBillwisePaymentHdr b1
left join (select @CompanyID CompanyID,@PeriodID PeriodID,@No No)b2 on b1.CompanyID=b2.CompanyID and b1.PeriodID=b2.PeriodID and b1.No=b2.No
join @Vendor v on b1.VendorID=v.ID
where b1.CompanyID=@CompanyID 
and b1.Advance>0 and b2.No is null
and isnull(Date,@OBDate) between @FromDate and @ToDate

;with p as
(select EPeriodID,EVoucherTypeID,ENo,ESNo,sum(Paid)Paid,sum(Discount)Discount,
 sum(case when Date<=@Date then Paid end)PUD,sum(case when Date<=@Date then Discount end)DUD 
 from aBillwisePaymentDtl d
 join aBillwisePaymentHdr h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.No=h.No
 join @Vendor v on h.VendorID=v.ID
 where not (d.CompanyID=@CompanyID and d.PeriodID=@PeriodID and d.No=@No)
 and d.CompanyID=@CompanyID and VendorID=@VendorID group by EPeriodID,EVoucherTypeID,ENo,ESNo)

update a set a.Amount=a.Amount-isnull(b.Paid,0)-isnull(b.Discount,0),a.BOD=a.Amount-isnull(b.PUD,0)-isnull(b.DUD,0) from @aTransaction a join p b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)

if @No>0
	update a set a.CHK=1,a.Paid=b.Paid,a.Discount=b.Discount from @aTransaction a 
	join aBillwisePaymentDtl b on isnull(a.PeriodID,0)=isnull(b.EPeriodID,0) and isnull(a.VoucherTypeID,0)=isnull(b.EVoucherTypeID,0) and isnull(a.No,0)=isnull(b.ENo ,0) and isnull(a.SNo,0)=isnull(b.ESNo ,0)
	where b.CompanyID=@CompanyID and b.PeriodID=@PeriodID and b.No=@No

--Due Date
if object_id('invVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join invVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join invPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID

if object_id('phyVoucherTypeDetails') is not null
	update a set a.DDate=ph.DueDate from @aTransaction a
	join phyVoucherTypeDetails v on a.VoucherTypeID=v.AccountVTypeID
	join phyPurchaseHeader ph on a.PeriodID=ph.PeriodID and v.ID=ph.VTypeID and a.No=ph.No
	where ph.CompanyID=@CompanyID


if @Type in(1,2)
Begin

	declare @DTDate smalldatetime
	set @DTDate=CURRENT_TIMESTAMP

	declare @Line varchar(13)
	set @Line=REPLICATE('_',13)

	declare @T table(Ord int,VendorID int,PeriodID int,AccountID int,Date int,VoucherTypeID int,No int,SNo int,Description nvarchar(200),Amount money,[ 0-30] money,[ 31-45] money,[ 46-60] money,[ 61-90] money,[ 90-] money)

	if exists(select top 1 1 from aAccount where UnderAccountID=@VendorID and ID<>UnderAccountID)
	Begin
		if @Type=1
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount,cast([ 0-30] as varchar)[ 0-30],cast([ 31-45] as varchar)[ 31-45],cast([ 46-60] as varchar)[ 46-60],cast([ 61-90] as varchar)[ 61-90],cast([ 90-] as varchar)[ 90-]	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount,cast(sum([ 0-30]) as varchar)[ 0-30],cast(sum([ 31-45]) as varchar)[ 31-45],cast(sum([ 46-60]) as varchar)[ 46-60],cast(sum([ 61-90]) as varchar)[ 61-90],cast(sum([ 90-]) as varchar)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line

		End
		Else
		Begin
			insert @T(Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)
			select row_number()over(partition by VendorID order by VendorID)Ord,VendorID,PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount
			from @aTransaction where round(Amount,4)<>0

			select case when Ord=1 then c.Name end LedgerAccount,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,cast(t.Amount as varchar)Amount	from @T t
			join aAccount a on t.AccountID=a.ID
			join @Vendor c on t.VendorID=c.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,cast(sum(Amount) as varchar)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line

		End
		

	End
	Else
	Begin
		if @Type=1
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,[ 0-30],[ 31-45],[ 46-60],[ 61-90],[ 90-])			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate)<31 then Amount end [ 0-30] ,
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 31 and 45 then Amount end [ 31-45],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 46 and 60 then Amount end [ 46-60],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) between 61 and 90 then Amount end [ 61-90],
			case when datediff(day,cast(cast(date as varchar) as smalldatetime),@DTDate) > 90 or Date is null then Amount end [ 90-]   
			from @aTransaction 
			where round(Amount,4)<>0
			order by Date
	
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,convert(varchar,t.Amount,4)Amount,convert(varchar,[ 0-30],4)[ 0-30],convert(varchar,[ 31-45],4)[ 31-45],convert(varchar,[ 46-60],4)[ 46-60],convert(varchar,[ 61-90],4)[ 61-90],convert(varchar,[ 90-],4)[ 90-] from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
			union all
			select null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount,convert(varchar,sum([ 0-30]),4)[ 0-30],convert(varchar,sum([ 31-45]),4)[ 31-45],convert(varchar,sum([ 46-60]),4)[ 46-60],convert(varchar,sum([ 61-90]),4)[ 61-90],convert(varchar,sum([ 90-]),4)[ 90-] from @T t
			union all
			select null,null,null,null,null,null,null,null,@Line,@Line,@Line,@Line,@Line,@Line
		End
		Else
		Begin
			insert @T(PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount)			
			select PeriodID,AccountID,Date,VoucherTypeID,No,SNo,Description,Amount from @aTransaction 
			where round(Amount,4)<>0
			order by Date
			
			select t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VType,t.No,t.SNo,a.Name Account,t.Description,datediff(day,cast(cast(date as varchar) as smalldatetime),CURRENT_TIMESTAMP)Age,convert(varchar,t.Amount,4)Amount from @T t
			join aAccount a on t.AccountID=a.ID
			left join aVoucherType v on t.VoucherTypeID=v.ID
			union all
			select null,null,null,null,null,null,null,null,null,@Line
			union all
			select null,null,null,null,null,null,null,null,null,convert(varchar,sum(Amount),4)Amount from @T t
			union all
			select null,null,null,null,null,null,null,null,null,@Line
		End
	End
End
Else
Begin
	select CHK,t.PeriodID,cast(cast(t.Date as varchar) as smalldatetime)Date,t.VoucherTypeID,v.Name VoucherType,t.No,t.RefNo,t.SNo,a.Name Account,
	t.Description,cast(cast(nullif(case when t.DDate<2099 then t.DDate end,0) as varchar) as smalldatetime)DDate,datediff(D,cast(cast(t.Date as varchar) as smalldatetime),current_timestamp)Age,t.BAmount,t.BOD,t.BAmount-t.Amount PPaid,t.Amount,t.Paid,t.Discount,null Balance from @aTransaction t
	join aAccount a on t.AccountID=a.ID
	left join aVoucherType v on t.VoucherTypeID=v.ID
	where round(t.Amount,2)<>0
	order by case when t.Amount>0 then 1 end,Date
End

go

if object_id('spGetSalesCollection') is not null drop proc spGetSalesCollection

go

create proc spGetSalesCollection
@CompanyID int,
@PeriodID int,
@FromDate int,
@ToDate int,
@AccountID int=null,
@OB bit,
@Type tinyint=null

as

declare @SC table(LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount nvarchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,CostCentre nvarchar(50))

insert @SC(LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Debit,Credit,AccountId,CostCentre,Company)
exec spLedger @CompanyID=@CompanyID,@PeriodID=@PeriodID,@FromDate=@FromDate,@ToDate=@ToDate,@AccountID=@AccountID,@OB=@OB,@Type=@Type


if object_id('invSalesDetails') is not null
Begin
	declare @Sales table(LedgerAccountID int,LedgerAccount varchar(100),Date smalldatetime,CompanyID int,VType varchar(50),No int,Account varchar(100),Description varchar(300),Qty float,Debit float,Credit float)	
		
	declare @LedgerAccounts table(LedgerAccountID int)
	insert @LedgerAccounts 
	select distinct LedgerAccountID from @SC

	declare @DSC table(CompanyID int,PeriodID int,VoucherTypeID int,No int)
	insert @DSC select distinct CompanyID int,PeriodID int,VoucherTypeID,No from  @SC

	--Normal Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name + '   ' +cast(d.Rate as varchar),d.Qty,d.Total,case when h.PaymentMode=0 then d.Total end from invSalesDetails d 
	join invSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on d.ProductID=p.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Advance',h.Paid from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Paid<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate and h.PaymentMode=1


	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Discount',case when h.PaymentMode=0 then h.Discount end,h.Discount from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Discount<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales','Addition',h.Addition,case when h.PaymentMode=0 then h.Addition end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	declare @AdditionCaption varchar(100),@RoundOffCaption varchar(100)
	select @RoundOffCaption=SalesRoundOffCaption from invOption where CompanyID=@CompanyID

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@RoundOffCaption,h.RoundOff,case when h.PaymentMode=0 then h.RoundOff end from invSalesHeader h 
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=h.CustomerID
	join @LedgerAccounts a on h.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where h.RoundOff<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--Multi Sales
	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,d.No,'Sales',p.Name,d.Qty,d.Gross,case when h.PaymentMode=0 then d.Gross end from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on d.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join invProduct p on h.ProductID=p.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	insert @Sales(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Debit,Credit)
	select aa.id,aa.name,cast(cast(h.Date as varchar)as smalldatetime),h.CompanyID,av.Name,h.No,'Sales',@AdditionCaption,case when h.PaymentMode=0 then abs(d.Addition) end,abs(d.Addition) from invMultiSalesDetails d 
	join invMultiSalesHeader h on d.CompanyID=h.CompanyID and d.PeriodID=h.PeriodID and d.VtypeID=h.VTypeID and d.No=h.No
	join invVoucherTypeDetails iv on h.VtypeID=iv.ID
	join aVoucherType av on iv.AccountVtypeID=av.ID
	join aAccount aa on aa.ID=d.CustomerID
	join @LedgerAccounts a on d.CustomerId=a.LedgerAccountID
	join @DSC s on s.CompanyID=h.CompanyID and s.PeriodID=h.PeriodID and s.VoucherTypeID=iv.AccountVtypeID and s.No=h.No
	where d.Addition<>0 and (@CompanyID=0 or h.CompanyID=@CompanyID) and h.Date between @FromDate and @ToDate

	--;with v as(select distinct vtype from @Sales)
	--delete s from @SC s join v on s.VType=v.VType

	delete s1 from @SC s1 join @Sales s2 on s1.CompanyID=s2.CompanyID and s1.Date=s2.Date and s1.VType=s2.VType and s1.No=s2.No 

End


insert @SC(LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit)
select LedgerAccountID,LedgerAccount,Date,CompanyID,VType,No,Account,Description,Qty,Debit,Credit from @Sales

--Company
if @CompanyID=0
	update l set l.Company=c.Name from @SC l join aCompany c on l.CompanyID=c.ID

--Rep Updation
--------------
declare @CRVTypeID int
select @CRVTypeID=CashReceipt from aVoucherTypeSettings

update s set s.Description = isnull(s.Description,'')+rp.Name from @SC s 
join aCashReceiptHdr r on s.VoucherTypeID=@CRVTypeID and s.No=r.No 
join invRep1 rp on r.RepID=rp.ID
where r.CompanyID=@CompanyID and r.PeriodID=@PeriodID
-------------------------------------------

--Balance
declare @SCB table(Ord int,LedgerAccountID int,LCode varchar(50),LedgerAccount varchar(100),CompanyID int,PeriodID int,Date smalldatetime,Company varchar(50),VoucherTypeID int,VType varchar(50),No int,SNo int,RefNo varchar(50),Code varchar(50),Account varchar(100),IAccount varchar(100),Description nvarchar(300),AdditionalDescription nvarchar(300),Qty float,Debit float,Credit float,AccountId int,Balance float,CostCentre nvarchar(50))

insert @SCB(Ord,LedgerAccountID,LCode,LedgerAccount,CompanyID,PeriodID,Date,Company,VoucherTypeID,VType,No,SNo,RefNo,Code,Account,IAccount,Description,AdditionalDescription,Qty,Debit,Credit,AccountId,CostCentre)
select row_number() over (partition by LedgerAccountID order by LedgerAccountID,Date,VoucherTypeID desc,No),* from @sc


;with b as
(select b.Ord,b.LedgerAccountID,sum(isnull(s.Debit,0)-isnull(s.Credit,0)) Balance from @SCB b join @SCB s on b.LedgerAccountID=s.LedgerAccountID and s.Ord<=b.Ord group by b.Ord,b.LedgerAccountID)

update s set s.Balance=b.Balance from @SCB s join b on s.LedgerAccountID=b.LedgerAccountID and s.Ord=b.Ord
-----------------


if exists(select 1 from aAccount where UnderAccountID=@AccountID and ID<>UnderAccountID)
	select case when Ord=1 then LedgerAccount end LedgerAccount,Date,VType,No,Account,Description,Debit,Credit,Balance from @SCB
else
Begin
	declare @Line varchar(25)
	set @Line=REPLICATE('-',25)
	select Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,Qty,Debit,Credit,Balance
	from
	(select 0 Ord,Date,Company,PeriodID,VoucherTypeID,VType,No,Account,Description,cast(Qty as varchar)Qty,convert(varchar,cast(Debit as money),4)Debit,convert(varchar,cast(Credit as money),4)Credit,convert(varchar,cast(Balance as money),4)Balance from @SCB
	union all
	select 1,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	union all
	select 2,null,null,null,null,null,null,null,null,cast(sum(Qty) as varchar),convert(varchar,cast(sum(Debit) as money),4),convert(varchar,cast(sum(Credit) as money),4),null from @SCB
	union all
	select 3,null,null,null,null,null,null,null,null,@Line,@Line,@Line,null
	)a
	Order by Ord,Date,VoucherTypeId desc,No
End
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

declare @Transaction table(CompanyId int,Date int,CostCentre varchar(50),VType varchar(50),No int,Customer nvarchar(100),Salesman varchar(100),Description varchar(100),Amount money,Discount money,VoucherTypeID int,PeriodID int,SalesmanId int,Account nvarchar(100))

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


