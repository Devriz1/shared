# shared
here you can find the latest exe

if not isnull({spGetInvSalesHeader;1.Cash}) and  not isnull({spGetInvSalesHeader;1.Bank}) then 
 {spGetInvSalesHeader;1.Cash} + {spGetInvSalesHeader;1.Bank}
else if not isnull({spGetInvSalesHeader;1.Bank}) then 
    {spGetInvSalesHeader;1.Bank}
else if not isnull({spGetInvSalesHeader;1.Cash}) then 
    {spGetInvSalesHeader;1.Cash}
else 
   0
