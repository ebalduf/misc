$template = Get-Template -name SElab-Templ2
$OSSpec = Get-OSCustomizationSpec -Name SElab-noQuestions

for ($i=1; $i -le 12; $i++) {
  stop-vm SElab-$i -Confirm:$false
  remove-vm SElab-$i -Confirm:$false -DeletePermanently:$true
  $dsnum = $i%2+1
  $datastore = 'SSD' + $dsnum 
  New-VM -Name SElab-$i -Template $template -OSCustomizationSpec $OSSpec -DiskStorageFormat Thin -datastore $datastore -VMHost 10.5.1.14
  start-vm SElab-$i -Confirm:$false
}