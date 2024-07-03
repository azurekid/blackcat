using namespace System.Management.Automation

class ValidServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($global:sessionVariables.serviceTags).values | Where-Object name -notlike '*.*'
    }
}

class ServiceNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        # $uri = ((Invoke-WebRequest -uri "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519").links | Where-Object outerHTML -like "*click here to download manually*").href
        # $uri = 'https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_20240701.json'
        $Values = ($global:SessionVariables.serviceTags | Where-Object name -notlike '*.*')
        return $Values.Name
    }
}