[CmdletBinding()]
param(
    [string]$TunnelPublicKey,
    [string[]]$CoordinatorPublicKey = @(),
    [string]$UserName = $env:USERNAME,
    [switch]$Complete
)
$ErrorActionPreference = 'Stop'
$base = 'C:\bandit-ai'
$model = "$base\models\andy.gguf"
$modelHash = '3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1'
$modelUrl = 'https://huggingface.co/Mindcraft-CE/Andy-4.2-GGUF/resolve/d3efcb8137c88cd3c23466ddabf985ea59b52fdf/andy-4.2.q4_k_m.gguf'
$llamaUrl = 'https://github.com/ggml-org/llama.cpp/releases/download/b11541/llama-b11541-bin-win-cuda-13.4-x64.zip'
$llamaHash = '927672eae5bb9cf4dde89a00a764c33e69e98db4b3d8be42f8990bf383cfdf61'
$cudaUrl = 'https://github.com/ggml-org/llama.cpp/releases/download/b11541/cudart-llama-bin-win-cuda-13.4-x64.zip'
$cudaHash = '738f8c251ac22b70c3ae6f83a10cf222725df0395246a2cf58f32bdb85fbe668'
$powerShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$embedded = @{
    'watch.ps1' = 'cGFyYW0oCiAgICBbc3dpdGNoXSRPbmNlLAogICAgW051bGxhYmxlW2ludF1dJEdwdVBlcmNlbnQgPSAkbnVsbCwKICAgIFtpbnRdJFRlc3RQb3J0ID0gMAopCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKJGJhc2UgPSAnQzpcYmFuZGl0LWFpJwokcnVudGltZSA9ICIkYmFzZVxydW50aW1lIgppZiAoLW5vdCAoVGVzdC1QYXRoICRydW50aW1lKSkgeyAkbnVsbCA9IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgJHJ1bnRpbWUgfQokbW9kZWwgPSAiJGJhc2VcbW9kZWxzXGFuZHkuZ2d1ZiIKJG1vZGVsU2hhMjU2ID0gJzNjZmNjYWExN2JlOGQyZGVkOTk4ZmFiOGJkNGI3MDMyZjkxZjJhOTE2YWMyYWEwM2E0MTI5MDgzNDIyMjhlYjEnCiRzY3JpcHQ6bW9kZWxGYWlsdXJlTG9nZ2VkID0gJGZhbHNlCiRwb3J0ID0gODA4MQokbGF5ZXJzID0gOTkKIyBBIENQVS1vbmx5IHNlY29uZCBzZXJ2ZXIgbGV0cyBjaGVja3MgbGVhdmUgdGhlIHJlcGxheSdzIEdQVSBzZXJ2ZXIgYWxvbmUuCmlmICgkVGVzdFBvcnQpIHsKICAgIGlmICgkVGVzdFBvcnQgLWxlIDEwMjQgLW9yICRUZXN0UG9ydCAtZ3QgNjU1MzUgLW9yICRUZXN0UG9ydCAtZXEgODA4MSkgeyB0aHJvdyAnSW52YWxpZCB0ZXN0IHBvcnQnIH0KICAgICRwb3J0ID0gJFRlc3RQb3J0CiAgICAkbGF5ZXJzID0gMAp9CiRtdXRleCA9IE5ldy1PYmplY3QgVGhyZWFkaW5nLk11dGV4KCRmYWxzZSwgIkxvY2FsXGJhbmRpdC1haS13YXRjaC0kcG9ydCIpCmlmICgtbm90ICRtdXRleC5XYWl0T25lKDApKSB7IGV4aXQgfQpBZGQtVHlwZSBAJwp1c2luZyBTeXN0ZW07CnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKcHVibGljIHN0YXRpYyBjbGFzcyBCYW5kaXRXaW5kb3cgewogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXSBwdWJsaWMgc3RydWN0IFJlY3QgeyBwdWJsaWMgaW50IExlZnQsIFRvcCwgUmlnaHQsIEJvdHRvbTsgfQogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIHVpbnQgV1RTR2V0QWN0aXZlQ29uc29sZVNlc3Npb25JZCgpOwogICAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBJbnRQdHIgR2V0Rm9yZWdyb3VuZFdpbmRvdygpOwogICAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBJbnRQdHIgR2V0U2hlbGxXaW5kb3coKTsKICAgIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdWludCBHZXRXaW5kb3dUaHJlYWRQcm9jZXNzSWQoSW50UHRyIGgsIG91dCB1aW50IHBpZCk7CiAgICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgR2V0V2luZG93UmVjdChJbnRQdHIgaCwgb3V0IFJlY3Qgcik7CiAgICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIEludFB0ciBNb25pdG9yRnJvbVdpbmRvdyhJbnRQdHIgaCwgdWludCBmbGFncyk7CiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldIHB1YmxpYyBzdHJ1Y3QgTW9uaXRvciB7IHB1YmxpYyBpbnQgU2l6ZTsgcHVibGljIFJlY3QgQm91bmRzLCBXb3JrOyBwdWJsaWMgdWludCBGbGFnczsgfQogICAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIEdldE1vbml0b3JJbmZvKEludFB0ciBoLCByZWYgTW9uaXRvciBtKTsKICAgIHB1YmxpYyBzdGF0aWMgdWludCBGb3JlZ3JvdW5kUGlkKCkgeyB1aW50IHBpZDsgR2V0V2luZG93VGhyZWFkUHJvY2Vzc0lkKEdldEZvcmVncm91bmRXaW5kb3coKSwgb3V0IHBpZCk7IHJldHVybiBwaWQ7IH0KICAgIHB1YmxpYyBzdGF0aWMgYm9vbCBGdWxsc2NyZWVuKCkgewogICAgICAgIHZhciBoID0gR2V0Rm9yZWdyb3VuZFdpbmRvdygpOwogICAgICAgIGlmIChoID09IEludFB0ci5aZXJvIHx8IGggPT0gR2V0U2hlbGxXaW5kb3coKSkgcmV0dXJuIGZhbHNlOwogICAgICAgIFJlY3QgcjsgdmFyIG0gPSBuZXcgTW9uaXRvcigpOyBtLlNpemUgPSBNYXJzaGFsLlNpemVPZihtKTsKICAgICAgICBpZiAoIUdldFdpbmRvd1JlY3QoaCwgb3V0IHIpIHx8ICFHZXRNb25pdG9ySW5mbyhNb25pdG9yRnJvbVdpbmRvdyhoLCAyKSwgcmVmIG0pKSB0aHJvdyBuZXcgRXhjZXB0aW9uKCJXaW5kb3cgcHJvYmUgZmFpbGVkIik7CiAgICAgICAgcmV0dXJuIHIuTGVmdCA8PSBtLkJvdW5kcy5MZWZ0ICYmIHIuVG9wIDw9IG0uQm91bmRzLlRvcCAmJiByLlJpZ2h0ID49IG0uQm91bmRzLlJpZ2h0ICYmIHIuQm90dG9tID49IG0uQm91bmRzLkJvdHRvbTsKICAgIH0KfQonQApmdW5jdGlvbiBXcml0ZS1Mb2coJG1lc3NhZ2UpIHsKICAgICRsb2cgPSAiJHJ1bnRpbWVcd2F0Y2gubG9nIgogICAgaWYgKChUZXN0LVBhdGggJGxvZykgLWFuZCAoR2V0LUl0ZW0gJGxvZykuTGVuZ3RoIC1nZSA1TUIpIHsgTW92ZS1JdGVtICRsb2cgIiRsb2cuMSIgLUZvcmNlIH0KICAgIEFkZC1Db250ZW50ICRsb2cgIiQoR2V0LURhdGUgLUZvcm1hdCBvKSBwb3J0PSRwb3J0ICRtZXNzYWdlIgp9CiRwaWRGaWxlID0gIiRydW50aW1lXHdhdGNoLSRwb3J0LnBpZCIKJHNlc3Npb24gPSAoR2V0LVByb2Nlc3MgLUlkICRQSUQpLlNlc3Npb25JZApmdW5jdGlvbiBMaXN0ZW5lcnMgewogICAgIyBFbnVtZXJhdGUgZmlyc3Q6IHF1ZXJ5aW5nIGFuIHVudXNlZCBMb2NhbFBvcnQgcmVwb3J0cyBhbiBlcnJvciwgbm90IGFuIGVtcHR5IGxpc3QuCiAgICBAKEdldC1OZXRUQ1BDb25uZWN0aW9uIC1TdGF0ZSBMaXN0ZW4gLUVycm9yQWN0aW9uIFN0b3AgfCBXaGVyZS1PYmplY3QgeyAkXy5Mb2NhbFBvcnQgLWVxICRwb3J0IH0pCn0KZnVuY3Rpb24gU2VydmVycygkbGlzdGVuZXJzKSB7CiAgICAkcmVjb3JkID0gJG51bGwKICAgIGlmIChUZXN0LVBhdGggJHBpZEZpbGUpIHsgJHJlY29yZCA9IEdldC1Db250ZW50ICRwaWRGaWxlIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uIH0KICAgIEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZT0nbGxhbWEtc2VydmVyLmV4ZSciIHwgV2hlcmUtT2JqZWN0IHsKICAgICAgICAkXy5FeGVjdXRhYmxlUGF0aCAtZXEgIiRiYXNlXGxsYW1hXGxsYW1hLXNlcnZlci5leGUiIC1hbmQKICAgICAgICAoKCgkXy5TZXNzaW9uSWQgLWVxICRzZXNzaW9uKSAtYW5kICRfLkNvbW1hbmRMaW5lIC1tYXRjaCAiLS1wb3J0XHMrJHBvcnQoPzpcc3wkKSIpIC1vcgogICAgICAgICAoJGxpc3RlbmVycy5Pd25pbmdQcm9jZXNzIC1jb250YWlucyAkXy5Qcm9jZXNzSWQpIC1vcgogICAgICAgICAoJHJlY29yZCAtYW5kICRfLlByb2Nlc3NJZCAtZXEgJHJlY29yZC5Qcm9jZXNzSWQgLWFuZAogICAgICAgICAgJF8uQ3JlYXRpb25EYXRlLlRvU3RyaW5nKCdvJykgLWVxICRyZWNvcmQuQ3JlYXRpb25EYXRlKSkKICAgIH0pCn0KZnVuY3Rpb24gQnVzeSB7CiAgICBpZiAoLW5vdCAkVGVzdFBvcnQgLWFuZCBbQmFuZGl0V2luZG93XTo6V1RTR2V0QWN0aXZlQ29uc29sZVNlc3Npb25JZCgpIC1uZSAoR2V0LVByb2Nlc3MgLUlkICRQSUQpLlNlc3Npb25JZCkgeyByZXR1cm4gJ2Fub3RoZXIgY29uc29sZSBzZXNzaW9uIChvciBubyBjb25zb2xlKScgfQogICAgIyBMaWdodCBnYW1lcyBuZXZlciBjb3VudCBhcyBnYW1lcyBhbmQgZG8gbm90IHRyaWdnZXIgdGhlIGZ1bGxzY3JlZW4gcnVsZSB3aGlsZSBmb2N1c2VkLgogICAgJGxpZ2h0ID0gQCgnaXNhYWMtbmcuZXhlJywgJ2lzYWFjLmV4ZScsICd3YWxscGFwZXI2NC5leGUnLCAnd2FsbHBhcGVyMzIuZXhlJykKICAgIGlmIChUZXN0LVBhdGggIiRiYXNlXGxpZ2h0LWdhbWVzLnR4dCIpIHsKICAgICAgICAkbGlnaHQgKz0gQChHZXQtQ29udGVudCAiJGJhc2VcbGlnaHQtZ2FtZXMudHh0IiB8IEZvckVhY2gtT2JqZWN0IHsgJF8uVHJpbSgpIH0gfCBXaGVyZS1PYmplY3QgeyAkXyAtYW5kIC1ub3QgJF8uU3RhcnRzV2l0aCgnIycpIH0pCiAgICB9CiAgICAkZm9yZWdyb3VuZCA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIlByb2Nlc3NJZD0kKFtCYW5kaXRXaW5kb3ddOjpGb3JlZ3JvdW5kUGlkKCkpIgogICAgJGxpZ2h0Rm9yZWdyb3VuZCA9ICRudWxsIC1uZSAkZm9yZWdyb3VuZCAtYW5kICRsaWdodCAtY29udGFpbnMgJGZvcmVncm91bmQuTmFtZQogICAgaWYgKC1ub3QgJGxpZ2h0Rm9yZWdyb3VuZCAtYW5kIFtCYW5kaXRXaW5kb3ddOjpGdWxsc2NyZWVuKCkpIHsgcmV0dXJuICdmdWxsc2NyZWVuIHdpbmRvdycgfQogICAgJGdhbWVzID0gQChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2VzcyB8IFdoZXJlLU9iamVjdCB7CiAgICAgICAgJF8uTmFtZSAtbm90aW4gJGxpZ2h0IC1hbmQgKAogICAgICAgICAgICAkXy5OYW1lIC1tYXRjaCAnXihNaW5lY3JhZnR8amF2YXd8Um9ibG94UGxheWVyQmV0YXxGb3J0bml0ZUNsaWVudC1XaW42NC1TaGlwcGluZ3xWQUxPUkFOVC1XaW42NC1TaGlwcGluZ3xjczJ8R1RBNXxSb2NrZXRMZWFndWUpXC5leGUkJyAtb3IKICAgICAgICAgICAgJF8uRXhlY3V0YWJsZVBhdGggLW1hdGNoICdcXChzdGVhbWFwcHNcXGNvbW1vbnxFcGljIEdhbWVzfFJpb3QgR2FtZXMpXFwnCiAgICAgICAgKQogICAgfSkKICAgIGlmICgkZ2FtZXMuQ291bnQpIHsgcmV0dXJuICJnYW1lICQoJGdhbWVzWzBdLk5hbWUpIiB9CiAgICBpZiAoJG51bGwgLW5lICRHcHVQZXJjZW50KSB7ICR1c2FnZSA9ICRHcHVQZXJjZW50IH0KICAgIGVsc2UgewogICAgICAgICRsbGFtYSA9IEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZT0nbGxhbWEtc2VydmVyLmV4ZSciIHwgRm9yRWFjaC1PYmplY3QgUHJvY2Vzc0lkKQogICAgICAgICRjb3VudGVycyA9IEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1BlcmZGb3JtYXR0ZWREYXRhX0dQVVBlcmZvcm1hbmNlQ291bnRlcnNfR1BVRW5naW5lKQogICAgICAgIGlmICgtbm90ICRjb3VudGVycy5Db3VudCkgeyB0aHJvdyAnTm8gR1BVIGVuZ2luZSBjb3VudGVyczsgcmVmdXNpbmcgaW5mZXJlbmNlJyB9CiAgICAgICAgJGVuZ2luZXMgPSBAe30KICAgICAgICBmb3JlYWNoICgkY291bnRlciBpbiAkY291bnRlcnMpIHsKICAgICAgICAgICAgaWYgKCRjb3VudGVyLk5hbWUgLW5vdG1hdGNoICdecGlkXyhcZCspXyguKykkJykgeyB0aHJvdyAnVW5yZWNvZ25pemVkIEdQVSBjb3VudGVyJyB9CiAgICAgICAgICAgIGlmICgkbGxhbWEgLWNvbnRhaW5zIFtpbnRdJE1hdGNoZXNbMV0pIHsgY29udGludWUgfQogICAgICAgICAgICAkZW5naW5lID0gJE1hdGNoZXNbMl0KICAgICAgICAgICAgJGVuZ2luZXNbJGVuZ2luZV0gKz0gW2ludF0kY291bnRlci5VdGlsaXphdGlvblBlcmNlbnRhZ2UKICAgICAgICB9CiAgICAgICAgJHVzYWdlID0gKCRlbmdpbmVzLlZhbHVlcyB8IE1lYXN1cmUtT2JqZWN0IC1NYXhpbXVtKS5NYXhpbXVtCiAgICB9CiAgICBpZiAoJHVzYWdlIC1nZSAyMCkgeyByZXR1cm4gIm5vbi1sbGFtYSBHUFUgJHVzYWdlJSIgfQogICAgcmV0dXJuICRudWxsCn0KJHNjcmlwdDptb2RlbENoZWNrID0gJG51bGwKZnVuY3Rpb24gTW9kZWxWZXJpZmllZCB7CiAgICAkaXRlbSA9IEdldC1JdGVtICRtb2RlbCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKC1ub3QgJGl0ZW0gLW9yICRpdGVtLlBTSXNDb250YWluZXIpIHsgcmV0dXJuICRmYWxzZSB9CiAgICAkc3RhbXAgPSAiJCgkaXRlbS5MZW5ndGgpOiQoJGl0ZW0uTGFzdFdyaXRlVGltZVV0Yy5UaWNrcykiCiAgICBpZiAoJHNjcmlwdDptb2RlbENoZWNrIC1hbmQgJHNjcmlwdDptb2RlbENoZWNrLlN0YW1wIC1lcSAkc3RhbXApIHsgcmV0dXJuICRzY3JpcHQ6bW9kZWxDaGVjay5WZXJpZmllZCB9CiAgICAkdmVyaWZpZWQgPSAoR2V0LUZpbGVIYXNoICRtb2RlbCAtQWxnb3JpdGhtIFNIQTI1NikuSGFzaC5Ub0xvd2VySW52YXJpYW50KCkgLWVxICRtb2RlbFNoYTI1NgogICAgJHNjcmlwdDptb2RlbENoZWNrID0gQHsgU3RhbXAgPSAkc3RhbXA7IFZlcmlmaWVkID0gJHZlcmlmaWVkIH0KICAgIHJldHVybiAkdmVyaWZpZWQKfQoKdHJ5IHsKICAgIGRvIHsKICAgICAgICAkY3ljbGUgPSBbRGlhZ25vc3RpY3MuU3RvcHdhdGNoXTo6U3RhcnROZXcoKQogICAgICAgIHRyeSB7CiAgICAgICAgICAgICRyZWFzb24gPSBCdXN5CiAgICAgICAgfSBjYXRjaCB7ICRyZWFzb24gPSAicHJvYmUgZmFpbGVkOiAkKCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSIgfQogICAgICAgIHRyeSB7CiAgICAgICAgICAgICRsaXN0ZW5lcnMgPSBAKExpc3RlbmVycykKICAgICAgICAgICAgJHNlcnZlcnMgPSBAKFNlcnZlcnMgJGxpc3RlbmVycykKICAgICAgICAgICAgaWYgKCRyZWFzb24pIHsKICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRzZXJ2ZXIgaW4gJHNlcnZlcnMpIHsKICAgICAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRzZXJ2ZXIuUHJvY2Vzc0lkIC1FcnJvckFjdGlvbiBTdG9wCiAgICAgICAgICAgICAgICAgICAgV3JpdGUtTG9nICJzdG9wcGVkIFBJRCAkKCRzZXJ2ZXIuUHJvY2Vzc0lkKTogJHJlYXNvbiIKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRsaXN0ZW5lciBpbiAkbGlzdGVuZXJzKSB7CiAgICAgICAgICAgICAgICAgICAgaWYgKCRzZXJ2ZXJzLlByb2Nlc3NJZCAtbm90Y29udGFpbnMgJGxpc3RlbmVyLk93bmluZ1Byb2Nlc3MpIHsKICAgICAgICAgICAgICAgICAgICAgICAgV3JpdGUtTG9nICJsZWZ0IGxpc3RlbmVyIFBJRCAkKCRsaXN0ZW5lci5Pd25pbmdQcm9jZXNzKTogbm90IG91cnMgdG8gc3RvcCAoJHJlYXNvbikiCiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9IGVsc2VpZiAoLW5vdCAkbGlzdGVuZXJzLkNvdW50IC1hbmQgLW5vdCAkc2VydmVycy5Db3VudCAtYW5kIChNb2RlbFZlcmlmaWVkKSkgewogICAgICAgICAgICAgICAgIyBWZXJpZmljYXRpb24gY2FuIHRha2Ugc2Vjb25kczsgYSBnYW1lIG1heSBoYXZlIHN0YXJ0ZWQgZHVyaW5nIGhhc2hpbmcuCiAgICAgICAgICAgICAgICBpZiAoQnVzeSkgeyB0aHJvdyAnR2FtZSBhcHBlYXJlZCBkdXJpbmcgbW9kZWwgdmVyaWZpY2F0aW9uOyBsYXVuY2ggZGVmZXJyZWQnIH0KICAgICAgICAgICAgICAgICRlbnY6TExBTUFfQVJHX0NIQVRfVEVNUExBVEVfS1dBUkdTID0gJ3siZW5hYmxlX3RoaW5raW5nIjpmYWxzZX0nCiAgICAgICAgICAgICAgICAkYXJndW1lbnRzID0gIi0tbW9kZWwgJGJhc2VcbW9kZWxzXGFuZHkuZ2d1ZiAtLWFsaWFzIGFuZHktNC4yLWJhc2VsaW5lIC0taG9zdCAxMjcuMC4wLjEgLS1wb3J0ICRwb3J0IC0tamluamEgLS1jdHgtc2l6ZSA4MTkyIC0tcGFyYWxsZWwgMSAtLW4tZ3B1LWxheWVycyAkbGF5ZXJzIC0tdGVtcCAwLjYgLS10b3AtayAyMCAtLXRvcC1wIDAuOTUgLS1taW4tcCAwIC0tcmVwZWF0LXBlbmFsdHkgMS4wIgogICAgICAgICAgICAgICAgJHNlcnZlciA9IFN0YXJ0LVByb2Nlc3MgIiRiYXNlXGxsYW1hXGxsYW1hLXNlcnZlci5leGUiIC1Bcmd1bWVudExpc3QgJGFyZ3VtZW50cyAtV29ya2luZ0RpcmVjdG9yeSAiJGJhc2VcbGxhbWEiIC1XaW5kb3dTdHlsZSBIaWRkZW4gLVBhc3NUaHJ1IC1SZWRpcmVjdFN0YW5kYXJkT3V0cHV0ICIkcnVudGltZVx3YXRjaC0kcG9ydC5vdXQubG9nIiAtUmVkaXJlY3RTdGFuZGFyZEVycm9yICIkcnVudGltZVx3YXRjaC0kcG9ydC5lcnIubG9nIgogICAgICAgICAgICAgICAgIyBDcmVhdGlvbiB0aW1lIHByZXZlbnRzIGEgc3RhbGUgUElEIGZpbGUgZnJvbSBhdXRob3JpemluZyBhIHJldXNlZCBQSUQuCiAgICAgICAgICAgICAgICAkc3RhcnRlZCA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIlByb2Nlc3NJZD0kKCRzZXJ2ZXIuSWQpIgogICAgICAgICAgICAgICAgQHsgUHJvY2Vzc0lkID0gJHNlcnZlci5JZDsgQ3JlYXRpb25EYXRlID0gJHN0YXJ0ZWQuQ3JlYXRpb25EYXRlLlRvU3RyaW5nKCdvJykgfSB8IENvbnZlcnRUby1Kc29uIHwgU2V0LUNvbnRlbnQgJHBpZEZpbGUKICAgICAgICAgICAgICAgIFdyaXRlLUxvZyAic3RhcnRlZCBQSUQgJCgkc2VydmVyLklkKSIKICAgICAgICAgICAgfSBlbHNlaWYgKC1ub3QgJGxpc3RlbmVycy5Db3VudCAtYW5kIC1ub3QgJHNlcnZlcnMuQ291bnQpIHsKICAgICAgICAgICAgICAgIGlmICgtbm90ICRzY3JpcHQ6bW9kZWxGYWlsdXJlTG9nZ2VkKSB7IFdyaXRlLUxvZyAibW9kZWwgbWlzc2luZyBvciBjaGVja3N1bSBtaXNtYXRjaDsgaW5mZXJlbmNlIGRpc2FibGVkIjsgJHNjcmlwdDptb2RlbEZhaWx1cmVMb2dnZWQgPSAkdHJ1ZSB9CiAgICAgICAgICAgIH0KICAgICAgICB9IGNhdGNoIHsgV3JpdGUtTG9nICJlcnJvcjogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiIH0KICAgICAgICBpZiAoLW5vdCAkT25jZSkgeyBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIChbTWF0aF06Ok1heCgwLCAxNTAwMCAtIFtpbnRdJGN5Y2xlLkVsYXBzZWRNaWxsaXNlY29uZHMpKSB9CiAgICB9IHdoaWxlICgtbm90ICRPbmNlKQp9IGZpbmFsbHkgewogICAgJG11dGV4LlJlbGVhc2VNdXRleCgpCiAgICAkbXV0ZXguRGlzcG9zZSgpCn0K'
    'watch.vbs' = 'U2V0IHNoZWxsID0gQ3JlYXRlT2JqZWN0KCJXU2NyaXB0LlNoZWxsIikKc2hlbGwuUnVuICJwb3dlcnNoZWxsLmV4ZSAtTm9Qcm9maWxlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlIEM6XGJhbmRpdC1haVx3YXRjaC5wczEiLCAwLCBGYWxzZQo='
    'light-games.txt' = 'IyBBZGQgZXhlY3V0YWJsZSBuYW1lcyBmb3IgZ2FtZXMgdGhhdCBzaG91bGQgbm90IHBhdXNlIGluZmVyZW5jZS4K'
}


function Assert-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from an elevated Windows PowerShell.' }
}
function Assert-NoLinks([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $items = @(Get-Item -LiteralPath $Path -Force) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force)
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Refusing reparse point under $Path" }
    }
}
function Set-ExactAcl([string]$Path, [string]$UserSid = '', [bool]$Writable = $false) {
    $directory = (Get-Item -LiteralPath $Path -Force).PSIsContainer
    $acl = if ($directory) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
    $acl.SetAccessRuleProtection($true, $false)
    $admin = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $acl.SetOwner($admin)
    $inherit = if ($directory) { [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' } else { [Security.AccessControl.InheritanceFlags]::None }
    foreach ($sid in 'S-1-5-32-544', 'S-1-5-18') {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', $inherit, 'None', 'Allow'))
    }
    if ($UserSid) {
        $rights = if ($Writable) { 'Modify' } else { 'ReadAndExecute' }
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($UserSid), $rights, $inherit, 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function KeyBlob([string]$Key) {
    if ($Key -match '(?:^|\s)(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521))\s+([A-Za-z0-9+/]+={0,2})(?:\s|$)') { return $Matches[1] }
    return ''
}
function Validate-Key([string]$Key) {
    if ($Key -match '[\r\n\x00]' -or $Key -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) +([A-Za-z0-9+/]+={0,2})(?: +[^\r\n]*)?$') { throw 'Supply a single bare OpenSSH public key, without options.' }
    $kind = $Matches[1]
    $bytes = [Convert]::FromBase64String($Matches[2])
    if ($bytes.Length -lt 8) { throw 'Invalid public key blob' }
    $length = $bytes[0] * 16777216 + $bytes[1] * 65536 + $bytes[2] * 256 + $bytes[3]
    if ($length -ne $kind.Length -or $bytes.Length -le 4 + $length -or [Text.Encoding]::ASCII.GetString($bytes, 4, $length) -ne $kind) { throw 'Invalid public key type in blob' }
}
function Set-AuthorizedKeys([string]$Path, [string[]]$Keys, [string]$UserSid = '') {
    $old = if (Test-Path $Path) { @(Get-Content $Path) } else { @() }
    $blobs = @($Keys | ForEach-Object { KeyBlob $_ })
    $kept = @($old | Where-Object { $blobs -notcontains (KeyBlob $_) })
    Set-Content -LiteralPath $Path -Value ($kept + $Keys) -Encoding ascii
    Set-ExactAcl $Path $UserSid
}
function Configure-Ssh {
    # Windows creates a broad rule when the capability is installed.
    Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue | Disable-NetFirewallRule | Out-Null
    $rule = Get-NetFirewallRule -Name Bandit-AI-SSH -ErrorAction SilentlyContinue
    if ($rule) { Remove-NetFirewallRule -Name Bandit-AI-SSH }
    New-NetFirewallRule -Name Bandit-AI-SSH -DisplayName 'bandit-ai sshd tailnet' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10 -Profile Any | Out-Null
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
}
function Download-Verified([string]$Url, [string]$Path, [string]$Hash) {
    if (-not (Test-Path $Path)) { Start-BitsTransfer -Source $Url -Destination $Path -Priority Low }
    if ((Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Hash) {
        Remove-Item -LiteralPath $Path -Force
        throw "Checksum mismatch: $Path; retry will download again"
    }
}
function Complete-Download {
    (Get-Process -Id $PID).PriorityClass = 'Idle'
    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
    Configure-Ssh
    if (Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object ExecutablePath -eq "$base\llama\llama-server.exe") { throw 'Existing server preserved; provisioning will retry when it stops.' }
    if (-not (Test-Path $model)) {
        Download-Verified $modelUrl "$model.part" $modelHash
        Move-Item "$model.part" $model
    } elseif ((Get-FileHash $model -Algorithm SHA256).Hash.ToLowerInvariant() -ne $modelHash) {
        throw 'Existing model checksum differs; move it aside explicitly before reinstalling.'
    }
    if (-not (Test-Path "$base\llama\llama-server.exe")) {
        $archive = "$base\llama.zip"
        Download-Verified $llamaUrl $archive $llamaHash
        $stage = "$base\llama.stage"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        Expand-Archive $archive $stage -Force
        $server = @(Get-ChildItem $stage -Recurse -Filter llama-server.exe)
        if ($server.Count -ne 1) { throw 'Expected exactly one llama-server.exe in archive' }
        $cudaArchive = "$base\cudart.zip"
        Download-Verified $cudaUrl $cudaArchive $cudaHash
        Expand-Archive $cudaArchive "$stage\runtime" -Force
        $dlls = @(Get-ChildItem "$stage\runtime" -Recurse -Filter *.dll)
        if (-not $dlls.Count) { throw 'CUDA runtime DLLs missing from archive' }
        foreach ($dll in $dlls) { Copy-Item $dll.FullName "$base\llama\$($dll.Name)" -Force }
        Get-ChildItem $server[0].Directory.FullName | Where-Object Name -ne 'llama-server.exe' | Copy-Item -Destination "$base\llama" -Recurse -Force
        # Publish the server only after its verified DLLs are in place.
        Move-Item $server[0].FullName "$base\llama\llama-server.exe"
        Remove-Item $stage -Recurse -Force
    }
}

Assert-Admin
if ($Complete) { Complete-Download; exit 0 }
if ($UserName -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Use the local Windows account name.' }
$userSid = ([Security.Principal.NTAccount]"$env:COMPUTERNAME\$UserName").Translate([Security.Principal.SecurityIdentifier]).Value
foreach ($key in @($TunnelPublicKey) + $CoordinatorPublicKey) { Validate-Key $key }
if (@($CoordinatorPublicKey | ForEach-Object { KeyBlob $_ }) -contains (KeyBlob $TunnelPublicKey)) { throw 'Coordinator key must differ from tunnel key.' }
$profile = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $userSid).LocalPath
if (-not $profile) { throw 'Target user must have logged in once before installing.' }
if (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '(?i)C:\\bandit-ai\\watch\.ps1' }) { throw 'Running watcher preserved. Sign out before upgrading its files.' }
if ((Get-ScheduledTask -TaskName bandit-ai-provision -ErrorAction SilentlyContinue).State -eq 'Running') { Write-Host 'Provisioning already running; existing installation preserved.'; exit 0 }
$ssh = "$profile\.ssh"
foreach ($path in $base, 'C:\ProgramData\ssh', $ssh) { Assert-NoLinks $path }
New-Item -ItemType Directory -Force -Path $base, "$base\models", "$base\llama", "$base\runtime", 'C:\ProgramData\ssh', $ssh | Out-Null
# Protect owners as well as DACLs before placing a script that SYSTEM will execute.
Set-ExactAcl $base $userSid
Set-ExactAcl 'C:\ProgramData\ssh'
foreach ($item in Get-ChildItem $base -Recurse -Force) {
    $writable = $item.FullName -eq "$base\runtime" -or $item.FullName.StartsWith("$base\runtime\", [StringComparison]::OrdinalIgnoreCase)
    Set-ExactAcl $item.FullName $userSid $writable
}
foreach ($name in $embedded.Keys) {
    if ($name -eq 'light-games.txt' -and (Test-Path "$base\$name")) { continue }
    [IO.File]::WriteAllBytes("$base\$name", [Convert]::FromBase64String($embedded[$name]))
    Set-ExactAcl "$base\$name" $userSid
}
if ([IO.Path]::GetFullPath($PSCommandPath) -ne "$base\install.ps1") { Copy-Item $PSCommandPath "$base\install.ps1" -Force }
Set-ExactAcl "$base\install.ps1" $userSid
$restricted = 'restrict,port-forwarding,permitopen="127.0.0.1:8081" ' + $TunnelPublicKey
Set-AuthorizedKeys 'C:\ProgramData\ssh\administrators_authorized_keys' (@($restricted) + $CoordinatorPublicKey)
Set-AuthorizedKeys "$ssh\authorized_keys" (@($restricted) + $CoordinatorPublicKey) $userSid

# Start installed sshd immediately; missing capability installation stays in the background.
if ((Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0).State -eq 'Installed') { Configure-Ssh }
$action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument 'C:\bandit-ai\watch.vbs'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$UserName"
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$UserName" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName bandit-ai-watch -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
$downloadAction = New-ScheduledTaskAction -Execute $powerShell -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\bandit-ai\install.ps1 -Complete'
$downloadPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$downloadSettings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName bandit-ai-provision -Action $downloadAction -Principal $downloadPrincipal -Settings $downloadSettings -Force | Out-Null
Start-ScheduledTask bandit-ai-provision
Write-Host 'Installed. Downloads continue at low priority. Watcher starts hidden at your next logon; it was not started now.'
