function ConvertTo-CliXml {
    param(
        [parameter(position=0,mandatory=$true,valuefrompipeline=$true)]
        [validatenotnull()]
        [psobject]$object
    )
    begin {
        $type = [psobject].assembly.gettype("System.Management.Automation.Serializer")
        $ctor = $type.getconstructor("instance,nonpublic", $null, @([xml.xmlwriter]), $null)
        $sw = new-object io.stringwriter
        $xw = new-object xml.xmltextwriter $sw
        $serializer = $ctor.invoke($xw)
        $method = $type.getmethod("Serialize", "nonpublic,instance", $null, [type[]]@([object]), $null)
        $done = $type.getmethod("Done", [reflection.bindingflags]"nonpublic,instance")
    }
    process {
        try {
            $method.invoke($serializer, $object)
        } catch {
            write-warning "Could not serialize $($object.gettype()): $_"
        }
    }
    end {    
        $done.invoke($serializer, @())
        $sw.ToString()
    }
}

<#
# ipmo poke
function ConvertTo-CliXml {
    param(
        [parameter(position=0,mandatory=$true,valuefrompipeline=$true)]
        [validatenotnull()]
        [psobject]$object
    )
    begin {
        $type = peek -name System.Management.Automation.Serializer
        $sw = new-object io.stringwriter
        $xw = new-object xml.xmltextwriter $sw

        # need to cast due to powershell not unwrapping array elements
        # from their psobject covers
        $serializer = $type.__createinstance([xml.xmltextwriter]$xw)
    }

    process {
        try {
            $serializer.Serialize($_)
        } catch {
            write-warning "Could not serialize $($object.gettype()): $_"
        }
    }

    end {
        $serializer.Done()
        $sw.tostring()
    }
}
#>