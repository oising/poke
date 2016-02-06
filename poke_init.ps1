# We run this outside of module scope in caller scope.
# We cannot use the manifest (PSD1) as it cannot override
# core formats because it uses -AppendPath semantics.

update-formatdata -PrependPath (join-path $psscriptroot 'Poke.Format.ps1xml')
