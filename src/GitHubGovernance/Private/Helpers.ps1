function Get-Prop {
    # Safe nested property access for StrictMode: Get-Prop $obj 'a.b.c'
    param($Object, [string] $Path)
    $current = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$part]) {
            return $null
        }
        $current = $current.$part
    }
    return $current
}
