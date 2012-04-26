function Invoke-Reflector {
<#
    .SYNOPSIS
        Quickly load Reflector, with the specified Type or Command selected. 
    .DESCRIPTION
        Quickly load Reflector, with the specified Type or Command selected. The function will also
        ensure that Reflector has the Type or Command's containing Assembly loaded.
    .EXAMPLE
        # Opens System.String in Reflector. Will load its Assembly into Reflector if required.
        ps> [string] | invoke-reflector    
    .EXAMPLE
        # Opens GetChildItemCommand in Reflector. Will load its Assembly into Reflector if required.
        ps> gcm ls | invoke-reflector        
    .EXAMPLE
        # Opens GetChildItemCommand in Reflector. Will load its Assembly into Reflector if required.
        ps> invoke-reflector dir        
    .PARAMETER CommandName
        Accepts name of command. Does not accept pipeline input.
    .PARAMETER CommandInfo
        Accepts output from Get-Command (gcm). Accepts pipeline input.
    .PARAMETER Type
        Accepts a System.Type (System.RuntimeType). Accepts pipeline input.
    .PARAMETER ReflectorPath
        Optional. Defaults to Reflector.exe's location if it is found in your $ENV:PATH. If not found, you must specify.
    .INPUTS
        [System.Type]
        [System.Management.Automation.CommandInfo]
    .OUTPUTS
        None
#>
     [cmdletbinding(defaultparametersetname="name")]
     param(
         [parameter(
            parametersetname="name",
            position=0,
            mandatory=$true
         )]
         [validatenotnullorempty()]
         [string]$CommandName,
         
         [parameter(
            parametersetname="command",
            position=0,
            valuefrompipeline=$true,
            mandatory=$true
         )]
         [validatenotnull()]
         [management.automation.commandinfo]$CommandInfo,
         
         [parameter(
            parametersetname="type",
            position=0,
            valuefrompipeline=$true,
            mandatory=$true
         )]
         [validatenotnull()]
         [type]$Type,
         
         [parameter(
            position=1
         )]
         [validatenotnullorempty()]
         [string]$ReflectorPath = $((gcm reflector.exe -ea 0).definition)
     )
     
    end {
        # no process block; i only want
        # a single reflector instance
        
        if ($ReflectorPath -and (test-path $reflectorpath)) {

            $typeName = $null            
            $assemblyLocation = $null
            
            switch ($pscmdlet.parametersetname) {
            
                 { "name","command" -contains $_ } {
                
                    if ($CommandName) {
                        $CommandInfo = gcm $CommandName -ea 0
                    } else {
                        $CommandName = $CommandInfo.Name
                    }
                    
                    if ($CommandInfo -is [management.automation.aliasinfo]) {
                        
                        # expand aliases
                        while ($CommandInfo.CommandType -eq "Alias") {
                            $CommandInfo = gcm $CommandInfo.Definition
                        }                                                
                    }
                    
                    # can only reflect cmdlets, obviously.
                    if ($CommandInfo.CommandType -eq "Cmdlet") {
                    
                        $typeName = $commandinfo.implementingtype.fullname
                        $assemblyLocation = $commandinfo.implementingtype.assembly.location
                    
                    } elseif ($CommandInfo) {
                        write-warning "$CommandInfo is not a Cmdlet."
                    } else {                    
                        write-warning "Cmdlet $CommandName does not exist in current scope. Have you loaded its containing module or snap-in?"
                    }
                }
                
                "type" {
                    $typeName = $type.fullname
                    $assemblyLocation = $type.assembly.location
                }                                
            } # end switch
            
            
            if ($typeName -and $assemblyLocation) {
                & $reflectorPath /select:$typeName $assemblyLocation
            }
            
        } else {
            write-warning "Unable to find Reflector.exe. Please specify full path via -ReflectorPath."
        }
    } # end end
} # end function
