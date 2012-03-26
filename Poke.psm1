###########################################
#
#             POKE Toolkit 0.2
#             By Oisin Grehan (MVP)
#
###########################################

Set-StrictMode -Version Latest

# method generator lambda
$initializer = {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    if ($baseObject.gettype().Name -eq "RuntimeType") {
        # type
        Write-Verbose "`$baseObject is a Type"
        $methodInfos = $baseobject.getmethods($flags)|?{!$_.isspecialname}
        $baseType = $baseObject
    } else {
        # instance
        Write-Verbose "`$baseObject is an instance"
        $methodInfos = $baseObject.GetType().getmethods($flags)|?{!$_.isspecialname}
        $baseType = $baseObject.GetType()
    }

    # [string].getmethod("Format", $binding, $null, $a, $null)

    foreach ($method in @($methodInfos|sort name -unique)) {
            
        $methodName = $method.name
        $returnType = $method.returnType

        write-verbose "Creating method $returntype $methodname`(...`)"
            
        # psscriptmethod ignores outputtype - maybe this will get fixed in later releases of ps?
        $definition = new-item function:$methodName -value ([scriptblock]::create("
            [outputtype('$returntype')]
            param();
                
            write-verbose 'called $methodName'
            [reflection.bindingflags]`$binding = '$flags'

            try {
                if ((`$overloads = @(`$baseType.getmethods(`$binding)|? name -eq '$methodname')).count -gt 1) {
                    write-verbose 'self $self ; flags: $flags ; finding best fit overload'
                    #write-warning ""multiple overloads (`$(`$overloads.count))""
                    `$types = @(`$args|%{`$_.gettype()})
                    `$method = `$baseType.getmethod('$methodname', `$binding, `$null, `$types, `$null)
                    if (-not `$method) {
                        write-warning ""Could not find best fit overload for `$(`$types -join ',').""
                        throw
                    }
                } else {
                    write-verbose 'single method; no overloads'
                }
                # invoke
                `$method.invoke(`$self, `$binding, `$null, `$args, `$null)                                    
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
<#

#>
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

        # define methods
        $self = $type
        . apply $initializer $type "Public,NonPublic,Static,DeclaredOnly"
                
        function __GetBaseObject {
            $type
        }
        
        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }
        
        function ToString {
            "[TypeProxy#$($type.FullName)]"
        }
        
        export-modulemember __CreateInstance, __GetBaseObject, __GetModuleInfo, ToString
        
    } -args $type, $initializer
    
    if ($typeProxy) {
        
        # TODO: fix up overloads
    
        $typeProxy.psobject.typenames.insert(0, "Pokeable.Object")
        $typeProxy.psobject.typenames.insert(0, "Pokeable.System.RuntimeType#$($type.fullname)")
        $typeProxy

        # TODO: create field/property initializer lambdas
        Add-fields $typeProxy "Public,NonPublic,DeclaredOnly,Static" > $null        
        Add-properties $typeProxy "Public,NonPublic,DeclaredOnly,Static" > $null
    }
}    

function New-InstanceProxy {
<#

#>
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true)]
        [validatenotnull()]
        [object]$Instance,
        [switch]$IncludeInheritedMembers, # not implemented
        [switch]$ExcludePublic, # not implemented
        [switch]$ExcludeFields # not implemented
    )
    
    $instanceId = [guid]::NewGuid()
        
    $type = $instance.GetType()
    
    #$methods = $type.GetMethods("Public,NonPublic,DeclaredOnly,Instance")|?{!$_.isspecialname}
        
    $wrapped = new-module -ascustomobject -name "$($type.Name)#$instanceId" -verbose {
        param(
            $self,
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

        . apply $initializer $self "Public,NonPublic,DeclaredOnly,Instance"

        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }

        function __GetBaseObject {
            $self
        }      
        
        function __Help {
            param([string]$MethodName)
            throw "Not implemented."
        }
        
        function ToString() {
            "Pokeable.$($type.FullName)#$instanceId"
        }
        
        export-modulemember __GetBaseObject, __GetModuleInfo, ToString #, __Help

        # register dispose handler on module remove
        $ExecutionContext.SessionState.Module.OnRemove = {

            # TODO: handle Close
            if ($self.Dispose) { # -as IDisposable?

                # will fail on explicit idisposable.dispose
                $self.Dispose()
            }
        }
    } -args $instance, $instanceId, $initializer
    
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
        
        Add-fields $wrapped "Public,NonPublic,DeclaredOnly,Instance" > $null
        
        Add-properties $wrapped "Public,NonPublic,DeclaredOnly,Instance" > $null

        $psobject.typenames.insert(0, "Pokeable.Object")
        $psobject.typenames.insert(0, "Pokeable.$($type.fullname)#$instanceId")
        
        $wrapped
    }
}

function Add-Fields {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    if ($baseObject.__GetBaseObject() -is [type]) {
        $type = $baseObject.__GetBaseObject()
        $self = $type
    } else {
        $type = $baseObject.__GetBaseObject().gettype()
        $self = $baseObject.__GetBaseObject()
    }

    $fields = $type.getfields($flags)
    $psobject = $baseObject.psobject

    # add fields
    foreach ($field in ($fields|sort name)) {
        # close over field and instance vars but insert literal for fieldtype
        $getter = [scriptblock]::create(
            "[outputtype('$($field.FieldType)')]param(); `$field.GetValue(`$self)").GetNewClosure()
        
        # declared readonly?
        if ($field.IsInitOnly) {
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter
        } else {
            $setter = { param($value); $field.SetValue($self, $value) }.GetNewClosure()
            
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter, $setter
        }
        write-verbose "Adding $flags field $($field.name)"
        $psobject.properties.add($fieldDef)
    }
}

function Add-Properties {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    if ($baseObject.__GetBaseObject() -is [type]) {
        $type = $baseObject.__GetBaseObject()
        $self = $type
    } else {
        $type = $baseObject.__GetBaseObject().gettype()
        $self = $baseObject.__GetBaseObject()
    }
    $properties = $type.getproperties($flags)
    $psobject = $baseObject.psobject
    

    # add properties
    foreach ($property in ($properties|sort name)) {
        # property getter
        $getter = [scriptblock]::create(
            "[outputtype('$($property.PropertyType)')]param(); `$property.GetValue(`$self)").GetNewClosure()
        
        # i don't account for setter-only properties
        if (-not $property.CanWrite) {
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter
        } else {
            # property setter
            $setter = { param($value); $property.SetValue($self, $value) }.GetNewClosure()            
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter, $setter
        }
        write-verbose "Adding $flags property $($property.name)"
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

    $assemblies = [appdomain]::CurrentDomain.GetAssemblies()
        
    $matches = @()
    
    $assemblies | % {
        write-verbose "Searching $($_.getname().name)..."
        
        $match = $_.gettype($typename, $false, !$CaseSensitive)
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
        [parameter(position=0, mandatory=$true, parametersetname="typeName")]
        [validatenotnullorempty()]
        [string]$TypeName,
        
        [parameter(position=0, mandatory=$true, parametersetname="type")]
        [validatenotnull()]
        [type]$Type,

        [parameter(parametersetname="typeName")]
        [switch]$CaseSensitive,
        
        [parameter(position=0, mandatory=$true, parametersetname="instance")]
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