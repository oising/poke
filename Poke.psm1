###########################################
#
#             POKE Toolkit 0.1
#             By Oisin Grehan (MVP)
#
###########################################

Set-StrictMode -Version Latest

# method generator lambda
$initializer = {
    param(
        [Parameter(mandatory=$true, position=0)]
        $baseObject,
        [parameter(mandatory=$true, position=1)]
        $methodInfos, # [collections.generic.ienumerable[reflection.methodinfo]]
        [Parameter(mandatory=$true, position=2)]
        [reflection.bindingflags]$flags
    )

    write-warning "METHOD initializer"

    foreach ($method in ($methodInfos|sort name -unique)) {
            
        $methodName = $method.name
        $returnType = $method.returnType

        write-verbose "Creating method $returntype $methodname`(...`)"
            
        # psscriptmethod ignores outputtype - maybe this will get fixed in later releases of ps?
        $definition = new-item function:$methodName -value ([scriptblock]::create("
            [outputtype('$returntype')]
            param();
                
            write-verbose 'called $methodName'
                
            try {
                    
                `$method.invoke(`$self, '$flags', `$null, `$args, `$null)
                    
            } catch {
                if (`$_.exception.innerexception -is [Reflection.TargetParameterCountException]) {
                        
                    write-warning ""Could not find matching overload with `$(`$args.count) parameter(s).""
                    # dump overloads (public methods only?)
                    `$self.$methodname
                        
                } else {
                    # error is from invocation target, rethrow
                    throw
                }
            }")).GetNewClosure()
            
        $definition.description = "Method $methodName"
        
        export-modulemember $methodname
        #$methodName
    }
}

function New-TypeProxy {
    [cmdletbinding()]
    param(        
        [parameter()]
        [validatenotnullorempty()]
        [string]$TypeName,
        [switch]$CaseSensitive
    )

    $type = Find-Type $typeName `
        -CaseSensitive:$CaseSensitive                

    if (-not $type) {
        write-warning "Could not find ${typeName}. Are you sure the containing assembly has been loaded?"
        return
    }
        
    # Create TypeProxy
    $typeProxy = new-module -ascustomobject -name "[${typeName}]" {
        param(
            [type]$type,
            [scriptblock]$initializer
        )
         
        Set-StrictMode -Version latest

        function apply {
            param([scriptblock]$block)
            . $ExecutionContext.SessionState.Module.NewBoundScriptBlock($block) @args
        }

        # skip accessors
        $methods = $type.GetMethods("Public,NonPublic,Static")|?{!$_.isspecialname}
    
        $properties = $type.GetProperties("Public,NonPublic,Static")

        function __CreateInstance {
            write-verbose "Type is $type ; `$args count is $($args.count)"

            if ($type.IsAbstract) {
                write-warning "Type is abstract."
                return
            }
            
            $types = @()
            $args|%{if($_ -eq $null){$types+=$null}else{$types+=$_.gettype()}}
            write-verbose ".ctor args: length $($types.length)"

            $ctor = $type.GetConstructor("Public,NonPublic,Instance", $null, $types, $null)

            if (-not $ctor) {
                write-warning "No matching constructor found. Available constructors:"
                $type.getconstructors("Public,NonPublic,Instance") | % { write-host -ForegroundColor Green " $_" }
                return 
            }

            # return wrapped object
            try {
                New-InstanceProxy $ctor.invoke($args) -verbose
            } catch {
                write-warning "Could not create instance: $_"
            }
        }

        . apply $initializer $type $methods "Public,NonPublic,Static"
                
        function __GetUnderlyingType {
            $type
        }
        
        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }
        
        function ToString {
            "[TypeProxy#$($type.FullName)]"
        }
        
        export-modulemember __CreateInstance, __GetUnderlyingType, __GetModuleInfo, ToString
        
    } -args $type, $initializer
    
    if ($typeProxy) {
        
        # TODO: fix up overloads
    
        $typeProxy.psobject.typenames.insert(0, "Pokeable.Object")
        $typeProxy.psobject.typenames.insert(0, "Pokeable.System.RuntimeType#$($type.fullname)")
        $typeProxy
    }
}    

function New-InstanceProxy {
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true)]
        [validatenotnull()]
        [object]$Instance,
        [switch]$ExcludePublic,
        [switch]$ExcludeFields
    )
    
    $instanceId = [guid]::NewGuid()
        
    $type = $instance.GetType()

    # TODO: also import static methods?
    $methods = $type.GetMethods("Public,NonPublic,DeclaredOnly,Instance")|?{!$_.isspecialname}
        
    $wrapped = new-module -ascustomobject -name "$($type.Name)#$instanceId" -verbose {
        param(
            $self,
            $methods,
            $instanceId,
            $initializer
        )
        
        Set-StrictMode -Version latest
    
        function apply {
            param([scriptblock]$block)
            . $ExecutionContext.SessionState.Module.NewBoundScriptBlock($block) @args
        }

        $type = $self.gettype()
        write-verbose "Created an instance of $type"

        . apply $initializer $self $methods "Public,NonPublic,Instance"

        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }

        function __GetInstance {
            $self
        }
        
        function __GetBaseInstance {
            throw "Not implemented."
        }
        
        function __Help {
            param([string]$MethodName)
            throw "Not implemented."
        }
        
        function ToString() {
            "Pokeable.$($type.FullName)#$instanceId"
        }
        
        export-modulemember __GetInstance, __GetModuleInfo, ToString #, __Help, __GetBaseInstance

        # register dispose handler on module remove
        $ExecutionContext.SessionState.Module.OnRemove = {

            # TODO: handle Close
            if ($self.Dispose) { # -as IDisposable?

                # will fail on explicit idisposable.dispose
                $self.Dispose()
            }
        }
    } -args $instance, $methods, $instanceId, $initializer
    
    if ($wrapped) {
    
        $psobject = $wrapped.psobject
        
        try {
            <# fix up overload definitions ;-)
            foreach ($method in ($methods|group name|sort name)) {
                $overloads = $psobject.methods[$method.name].overloaddefinitions
                write-verbose $($method.name + " has " + $method.group.count + " overload(s)")
                $overloads.clear()
                $method.group | % { $overloads.add($_) }
            }
            #>
        } catch {
            write-warning "Failed to fix up overloads: $_"        
        }
        
        append-fields $wrapped "Public,NonPublic,DeclaredOnly,Instance" > $null
        
        append-properties $wrapped "Public,NonPublic,DeclaredOnly,Instance" > $null

        $psobject.typenames.insert(0, "Pokeable.Object")
        $psobject.typenames.insert(0, "Pokeable.$($type.fullname)#$instanceId")
        
        $wrapped
    }
}

function Append-Fields {
    param(
        $wrapped,        
        [reflection.bindingflags]$binding
    )

    $type = $wrapped.__GetInstance().gettype()
    $fields = $type.getfields($binding)
    $psobject = $wrapped.psobject
    $instance = $Wrapped.__GetInstance()

    # add fields
    foreach ($field in ($fields|sort name)) {
        # close over field and instance vars but insert literal for fieldtype
        $getter = [scriptblock]::create(
            "[outputtype('$($field.FieldType)')]param(); `$field.GetValue(`$instance)").GetNewClosure()
        
        # declared readonly?
        if ($field.IsInitOnly) {
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter
        } else {
            $setter = { param($value); $field.SetValue($instance, $value) }.GetNewClosure()
            
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter, $setter
        }
        write-verbose "Adding field $($field.name)"
        $psobject.properties.add($fieldDef)
    }
}

function Append-Properties {
    param(        
        $wrapped,        
        [reflection.bindingflags]$binding
    )

    $type = $wrapped.__GetInstance().gettype()
    $properties = $type.getproperties($binding)
    $psobject = $wrapped.psobject
    $instance = $Wrapped.__GetInstance()

    # add properties
    foreach ($property in ($properties|sort name)) {
        # property getter
        $getter = [scriptblock]::create(
            "[outputtype('$($property.PropertyType)')]param(); `$property.GetValue(`$instance)").GetNewClosure()
        
        # i don't account for setter-only properties
        if (-not $property.CanWrite) {
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter
        } else {
            # property setter
            $setter = { param($value); $property.SetValue($instance, $value) }.GetNewClosure()            
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter, $setter
        }
        write-verbose "Adding property $($property.name)"
        $psObject.properties.add($propertyDef)
    }
}

function Find-Type {
    param(
        [string]$TypeName,
        [reflection.bindingflags]$BindingFlags = "Public,NonPublic",
        [switch]$CaseSensitive
    )
    
    write-verbose "Searching for $typeName"
    
    $ps = @(
        'CompiledComposition.Microsoft.PowerShell.GPowerShell',
        'Microsoft.PowerShell.Commands.Diagnostics',
        'Microsoft.PowerShell.Commands.Management',
        'Microsoft.PowerShell.Commands.Utility',
        'Microsoft.PowerShell.ConsoleHost',
        'Microsoft.PowerShell.Editor',
        'Microsoft.PowerShell.GPowerShell',
        'Microsoft.PowerShell.Security',
        'Microsoft.WSMan.Management',
        'powershell_ise',
        'PSEventHandler',
        'System.Management.Automation')
        
    $wpf = @(
        'PresentationCore',
        'PresentationFramework', 
        'PresentationFramework.Aero',
        'WindowsBase',
        'UIAutomationProvider',
        'UIAutomationTypes')

    $assemblies = [appdomain]::CurrentDomain.GetAssemblies() #| ? {
#        (!($_.getname().name -match '(mscorlib|^System$|^System\..*)')) -or $IncludeDotNetAssemblies} | ? {
#        (!($ps -contains $_.getname().name)) -or $IncludePowershellAssemblies } | ? {
#        (!($wpf -contains $_.getname().name)) -or $IncludeWPFAssemblies }
        
    $matches = @()
    
    $assemblies | % {
        write-verbose "Searching $($_.getname().name)..."
        
        $match = $_.gettype($typename, $false, $CaseSensitive)
        if ($match) {
            $matches += $match
        }        
    }
    
    write-verbose "Found $($matches.length) match(es)."
        
    $matches
}

function New-ObjectProxy {
    [cmdletbinding(defaultparametersetname="typeName")]
    param(                
        [parameter(mandatory=$true, parametersetname="typeName")]
        [validatenotnullorempty()]
        [string]$TypeName,
        
        [parameter(mandatory=$true, parametersetname="type")]
        [validatenotnull()]
        [type]$Type,

        [parameter(parametersetname="type")]
        [parameter(parametersetname="typeName")]
        [switch]$CaseSensitive,
        
        [parameter(mandatory=$true, parametersetname="instance")]
        [validatenotnull()]
        [object]$Instance
    )
    
    if ($PSCmdlet.ParameterSetName -eq "instance") {
    
        New-InstanceProxy -instance $instance
    
    } else {
        
        if ($PSCmdlet.ParameterSetName -eq "type") {
            $typeName = $type.fullname
        }
        
        New-TypeProxy -TypeName $TypeName -CaseSensitive:$CaseSensitive
    }
}

new-alias -Name peek -Value New-ObjectProxy -Force
Export-ModuleMember -Alias peek -Function New-ObjectProxy, New-TypeProxy, New-InstanceProxy