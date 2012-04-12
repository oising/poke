

update-formatdata -PrependPath (join-path $psscriptroot 'Poke.Format.ps1xml')

<#
Update-TypeData -typename Microsoft.PowerShell.Commands.MemberDefinition -MemberType ScriptProperty -MemberName MemberType -Value {    
    try { invoke-formathelper $this get-membertype } catch { write-warning "oops: $_" }
} -Force

Update-TypeData -typename Microsoft.PowerShell.Commands.MemberDefinition -MemberType ScriptProperty -MemberName Modifier -Value {    
    try { invoke-formathelper $this get-membermodifier } catch { write-warning "oops: $_" }
} -Force
#>