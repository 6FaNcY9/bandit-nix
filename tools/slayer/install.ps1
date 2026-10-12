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
    'watch.ps1' = 'cGFyYW0oCiAgICBbc3dpdGNoXSRPbmNlLAogICAgW051bGxhYmxlW2ludF1dJEdwdVBlcmNlbnQgPSAkbnVsbCwKICAgIFtpbnRdJFRlc3RQb3J0ID0gMAopCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKJGJhc2UgPSAnQzpcYmFuZGl0LWFpJwokcnVudGltZSA9ICIkYmFzZVxydW50aW1lIgppZiAoLW5vdCAoVGVzdC1QYXRoICRydW50aW1lKSkgeyAkbnVsbCA9IE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgJHJ1bnRpbWUgfQokbW9kZWwgPSAiJGJhc2VcbW9kZWxzXGFuZHkuZ2d1ZiIKJG1vZGVsU2hhMjU2ID0gJzNjZmNjYWExN2JlOGQyZGVkOTk4ZmFiOGJkNGI3MDMyZjkxZjJhOTE2YWMyYWEwM2E0MTI5MDgzNDIyMjhlYjEnCiRzY3JpcHQ6bW9kZWxGYWlsdXJlTG9nZ2VkID0gJGZhbHNlCiRzY3JpcHQ6ZnJlZVNpbmNlID0gJG51bGwKJHBvcnQgPSA4MDgxCiRsYXllcnMgPSA5OQojIEEgQ1BVLW9ubHkgc2Vjb25kIHNlcnZlciBsZXRzIGNoZWNrcyBsZWF2ZSB0aGUgcmVwbGF5J3MgR1BVIHNlcnZlciBhbG9uZS4KaWYgKCRUZXN0UG9ydCkgewogICAgaWYgKCRUZXN0UG9ydCAtbGUgMTAyNCAtb3IgJFRlc3RQb3J0IC1ndCA2NTUzNSAtb3IgJFRlc3RQb3J0IC1lcSA4MDgxKSB7IHRocm93ICdJbnZhbGlkIHRlc3QgcG9ydCcgfQogICAgJHBvcnQgPSAkVGVzdFBvcnQKICAgICRsYXllcnMgPSAwCn0KJG11dGV4ID0gTmV3LU9iamVjdCBUaHJlYWRpbmcuTXV0ZXgoJGZhbHNlLCAiTG9jYWxcYmFuZGl0LWFpLXdhdGNoLSRwb3J0IikKaWYgKC1ub3QgJG11dGV4LldhaXRPbmUoMCkpIHsgZXhpdCB9CiMgQnVzeSBwcm9iZSBzaGFyZWQgd2l0aCB0cmFpblxydW4tZ3VhcmRlZC5wczEgKEM6XGJhbmRpdC1haVxidXN5LnBzMSkuCi4gIiRiYXNlXGJ1c3kucHMxIgpmdW5jdGlvbiBXcml0ZS1Mb2coJG1lc3NhZ2UpIHsKICAgICRsb2cgPSAiJHJ1bnRpbWVcd2F0Y2gubG9nIgogICAgaWYgKChUZXN0LVBhdGggJGxvZykgLWFuZCAoR2V0LUl0ZW0gJGxvZykuTGVuZ3RoIC1nZSA1TUIpIHsgTW92ZS1JdGVtICRsb2cgIiRsb2cuMSIgLUZvcmNlIH0KICAgIEFkZC1Db250ZW50ICRsb2cgIiQoR2V0LURhdGUgLUZvcm1hdCBvKSBwb3J0PSRwb3J0ICRtZXNzYWdlIgp9CiRwaWRGaWxlID0gIiRydW50aW1lXHdhdGNoLSRwb3J0LnBpZCIKJHNlc3Npb24gPSAoR2V0LVByb2Nlc3MgLUlkICRQSUQpLlNlc3Npb25JZApmdW5jdGlvbiBMaXN0ZW5lcnMgewogICAgIyBFbnVtZXJhdGUgZmlyc3Q6IHF1ZXJ5aW5nIGFuIHVudXNlZCBMb2NhbFBvcnQgcmVwb3J0cyBhbiBlcnJvciwgbm90IGFuIGVtcHR5IGxpc3QuCiAgICBAKEdldC1OZXRUQ1BDb25uZWN0aW9uIC1TdGF0ZSBMaXN0ZW4gLUVycm9yQWN0aW9uIFN0b3AgfCBXaGVyZS1PYmplY3QgeyAkXy5Mb2NhbFBvcnQgLWVxICRwb3J0IH0pCn0KZnVuY3Rpb24gU2VydmVycygkbGlzdGVuZXJzKSB7CiAgICAkcmVjb3JkID0gJG51bGwKICAgIGlmIChUZXN0LVBhdGggJHBpZEZpbGUpIHsgJHJlY29yZCA9IEdldC1Db250ZW50ICRwaWRGaWxlIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uIH0KICAgIEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiTmFtZT0nbGxhbWEtc2VydmVyLmV4ZSciIHwgV2hlcmUtT2JqZWN0IHsKICAgICAgICAkXy5FeGVjdXRhYmxlUGF0aCAtZXEgIiRiYXNlXGxsYW1hXGxsYW1hLXNlcnZlci5leGUiIC1hbmQKICAgICAgICAoKCgkXy5TZXNzaW9uSWQgLWVxICRzZXNzaW9uKSAtYW5kICRfLkNvbW1hbmRMaW5lIC1tYXRjaCAiLS1wb3J0XHMrJHBvcnQoPzpcc3wkKSIpIC1vcgogICAgICAgICAoJGxpc3RlbmVycy5Pd25pbmdQcm9jZXNzIC1jb250YWlucyAkXy5Qcm9jZXNzSWQpIC1vcgogICAgICAgICAoJHJlY29yZCAtYW5kICRfLlByb2Nlc3NJZCAtZXEgJHJlY29yZC5Qcm9jZXNzSWQgLWFuZAogICAgICAgICAgJF8uQ3JlYXRpb25EYXRlLlRvU3RyaW5nKCdvJykgLWVxICRyZWNvcmQuQ3JlYXRpb25EYXRlKSkKICAgIH0pCn0KIyBHYW1lcyBsZWF2ZSB0aGUgR1BVIHRvIHRoZSBnYW1lIGJ1dCBub3QgdG8gQW5keTogJ3NoYXJlZCcgc2VydmVzIG9uIHRoZSBWUkFNIHRoZXkgbGVhdmUgZnJlZQojIChDUFUgb25seSwgbG93IHByaW9yaXR5KSwgJ2Z1bGwnIGlzIHRoZSBub3JtYWwgYWxsLWxheWVycyBzZXJ2ZXIuICRudWxsIHN0b3BzIHRoZSBzZXJ2ZXIgKHRyYWluaW5nLAojIGFub3RoZXIgY29uc29sZSBzZXNzaW9uLCBwcm9iZSBmYWlsdXJlcykuIEJhY2sgdG8gZnVsbCBvbmx5IGFmdGVyIDUgbWluIG9mIGEgZnJlZSBQQywgc28KIyBhbHQtdGFiYmluZyBkb2VzIG5vdCByZXN0YXJ0IHRoZSBzZXJ2ZXIuCmZ1bmN0aW9uIFBpY2tNb2RlKCRyZWFzb24sICRjdXJyZW50KSB7CiAgICBpZiAoJHJlYXNvbiAtYW5kICRyZWFzb24gLW5vdG1hdGNoICdeKGZ1bGxzY3JlZW4gd2luZG93fGdhbWUgfG5vbi1sbGFtYSBHUFUpJykgeyByZXR1cm4gJG51bGwgfQogICAgaWYgKC1ub3QgJHJlYXNvbiAtYW5kICRjdXJyZW50IC1lcSAnc2hhcmVkJyAtYW5kICRzY3JpcHQ6ZnJlZVNpbmNlIC1hbmQgKChHZXQtRGF0ZSkgLSAkc2NyaXB0OmZyZWVTaW5jZSkuVG90YWxNaW51dGVzIC1sdCA1KSB7IHJldHVybiAnc2hhcmVkJyB9CiAgICBpZiAoJHJlYXNvbikgeyByZXR1cm4gJ3NoYXJlZCcgfQogICAgcmV0dXJuICdmdWxsJwp9CmZ1bmN0aW9uIFNlcnZlck1vZGUoJHNlcnZlcikgeyBpZiAoJHNlcnZlci5Db21tYW5kTGluZSAtbWF0Y2ggJy0tcHJpb1xzKy0xKD86XHN8JCknKSB7ICdzaGFyZWQnIH0gZWxzZSB7ICdmdWxsJyB9IH0KIyB0cmFpblxydW4tZ3VhcmRlZC5wczEgaG9sZHMgQzpcYmFuZGl0LWFpXHRyYWluaW5nLmxvY2sgd2hpbGUgaXQgdHJhaW5zOiB0aGUgR1BVIGlzIGl0cywgc28gdGhlCiMgc2VydmVyIGlzIHN0b3BwZWQgYW5kIG5vdCBzdGFydGVkLiBBIGxvY2sgb2xkZXIgdGhhbiAyNCBoIGlzIGEgY3Jhc2ggbGVmdG92ZXIgYW5kIGlnbm9yZWQuCmZ1bmN0aW9uIFRyYWluaW5nIHsKICAgICRsb2NrID0gR2V0LUl0ZW0gIiRiYXNlXHRyYWluaW5nLmxvY2siIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICBpZiAoJGxvY2sgLWFuZCAoKEdldC1EYXRlKSAtICRsb2NrLkxhc3RXcml0ZVRpbWUpLlRvdGFsSG91cnMgLWx0IDI0KSB7IHJldHVybiAndHJhaW5pbmcnIH0KICAgIHJldHVybiAkbnVsbAp9CiRzY3JpcHQ6bW9kZWxDaGVja3MgPSBAe30KZnVuY3Rpb24gTW9kZWxWZXJpZmllZChbc3RyaW5nXSRwYXRoID0gJG1vZGVsLCBbc3RyaW5nXSRzaGEyNTYgPSAkbW9kZWxTaGEyNTYpIHsKICAgICRpdGVtID0gR2V0LUl0ZW0gJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgIGlmICgtbm90ICRpdGVtIC1vciAkaXRlbS5QU0lzQ29udGFpbmVyKSB7IHJldHVybiAkZmFsc2UgfQogICAgJHN0YW1wID0gIiQoJGl0ZW0uTGVuZ3RoKTokKCRpdGVtLkxhc3RXcml0ZVRpbWVVdGMuVGlja3MpIgogICAgJGNoZWNrID0gJHNjcmlwdDptb2RlbENoZWNrc1skcGF0aF0KICAgIGlmICgkY2hlY2sgLWFuZCAkY2hlY2suU3RhbXAgLWVxICRzdGFtcCkgeyByZXR1cm4gJGNoZWNrLlZlcmlmaWVkIH0KICAgICR2ZXJpZmllZCA9IChHZXQtRmlsZUhhc2ggJHBhdGggLUFsZ29yaXRobSBTSEEyNTYpLkhhc2guVG9Mb3dlckludmFyaWFudCgpIC1lcSAkc2hhMjU2LlRvTG93ZXJJbnZhcmlhbnQoKQogICAgJHNjcmlwdDptb2RlbENoZWNrc1skcGF0aF0gPSBAeyBTdGFtcCA9ICRzdGFtcDsgVmVyaWZpZWQgPSAkdmVyaWZpZWQgfQogICAgcmV0dXJuICR2ZXJpZmllZAp9CiMgT3B0aW9uYWwgY2FuZGlkYXRlIG1vZGVsIChDOlxiYW5kaXQtYWlcY2FuZGlkYXRlLmpzb24ge2ZpbGUsIHNoYTI1NiwgYWxpYXN9KTogc2VydmVkIGluc3RlYWQgb2YKIyBhbmR5LmdndWYgb25seSB3aGlsZSBpdHMgZmlsZSBpbiBtb2RlbHNcIGV4aXN0cyBhbmQgbWF0Y2hlcyB0aGUgaGFzaC4gRGVsZXRlIHRoZSBqc29uIHRvIGdvIGJhY2suCmZ1bmN0aW9uIFNlcnZpbmcgewogICAgdHJ5IHsKICAgICAgICBpZiAoVGVzdC1QYXRoICIkYmFzZVxjYW5kaWRhdGUuanNvbiIpIHsKICAgICAgICAgICAgJGMgPSBHZXQtQ29udGVudCAiJGJhc2VcY2FuZGlkYXRlLmpzb24iIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uCiAgICAgICAgICAgIGlmICgkYy5maWxlIC1tYXRjaCAnXltBLVphLXowLTlfLi1dK1wuZ2d1ZiQnIC1hbmQgJGMuc2hhMjU2IC1tYXRjaCAnXlswLTlhLWZBLUZdezY0fSQnIC1hbmQgJGMuYWxpYXMgLW1hdGNoICdeW0EtWmEtejAtOV8uLV0rJCcgLWFuZCAoTW9kZWxWZXJpZmllZCAiJGJhc2VcbW9kZWxzXCQoJGMuZmlsZSkiICRjLnNoYTI1NikpIHsKICAgICAgICAgICAgICAgIHJldHVybiBAeyBQYXRoID0gIiRiYXNlXG1vZGVsc1wkKCRjLmZpbGUpIjsgQWxpYXMgPSAkYy5hbGlhcyB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9IGNhdGNoIHsgfQogICAgaWYgKE1vZGVsVmVyaWZpZWQpIHsgcmV0dXJuIEB7IFBhdGggPSAkbW9kZWw7IEFsaWFzID0gJ2FuZHktNC4yLWJhc2VsaW5lJyB9IH0KICAgIHJldHVybiAkbnVsbAp9Cgp0cnkgewogICAgZG8gewogICAgICAgICRjeWNsZSA9IFtEaWFnbm9zdGljcy5TdG9wd2F0Y2hdOjpTdGFydE5ldygpCiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJHJlYXNvbiA9IFRyYWluaW5nCiAgICAgICAgICAgIGlmICgtbm90ICRyZWFzb24pIHsgJHJlYXNvbiA9IEJ1c3kgfQogICAgICAgIH0gY2F0Y2ggeyAkcmVhc29uID0gInByb2JlIGZhaWxlZDogJCgkXy5FeGNlcHRpb24uTWVzc2FnZSkiIH0KICAgICAgICBpZiAoJHJlYXNvbikgeyAkc2NyaXB0OmZyZWVTaW5jZSA9ICRudWxsIH0gZWxzZWlmICgtbm90ICRzY3JpcHQ6ZnJlZVNpbmNlKSB7ICRzY3JpcHQ6ZnJlZVNpbmNlID0gR2V0LURhdGUgfQogICAgICAgIHRyeSB7CiAgICAgICAgICAgICRsaXN0ZW5lcnMgPSBAKExpc3RlbmVycykKICAgICAgICAgICAgJHNlcnZlcnMgPSBAKFNlcnZlcnMgJGxpc3RlbmVycykKICAgICAgICAgICAgJG1vZGUgPSBQaWNrTW9kZSAkcmVhc29uICQoaWYgKCRzZXJ2ZXJzLkNvdW50KSB7IFNlcnZlck1vZGUgJHNlcnZlcnNbMF0gfSkKICAgICAgICAgICAgaWYgKC1ub3QgJG1vZGUpIHsKICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRzZXJ2ZXIgaW4gJHNlcnZlcnMpIHsKICAgICAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRzZXJ2ZXIuUHJvY2Vzc0lkIC1FcnJvckFjdGlvbiBTdG9wCiAgICAgICAgICAgICAgICAgICAgV3JpdGUtTG9nICJzdG9wcGVkIFBJRCAkKCRzZXJ2ZXIuUHJvY2Vzc0lkKTogJHJlYXNvbiIKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRsaXN0ZW5lciBpbiAkbGlzdGVuZXJzKSB7CiAgICAgICAgICAgICAgICAgICAgaWYgKCRzZXJ2ZXJzLlByb2Nlc3NJZCAtbm90Y29udGFpbnMgJGxpc3RlbmVyLk93bmluZ1Byb2Nlc3MpIHsKICAgICAgICAgICAgICAgICAgICAgICAgV3JpdGUtTG9nICJsZWZ0IGxpc3RlbmVyIFBJRCAkKCRsaXN0ZW5lci5Pd25pbmdQcm9jZXNzKTogbm90IG91cnMgdG8gc3RvcCAoJHJlYXNvbikiCiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICB9IGVsc2VpZiAoJHNlcnZlcnMgfCBXaGVyZS1PYmplY3QgeyAoU2VydmVyTW9kZSAkXykgLW5lICRtb2RlIH0pIHsKICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRzZXJ2ZXIgaW4gJHNlcnZlcnMpIHsKICAgICAgICAgICAgICAgICAgICBTdG9wLVByb2Nlc3MgLUlkICRzZXJ2ZXIuUHJvY2Vzc0lkIC1FcnJvckFjdGlvbiBTdG9wCiAgICAgICAgICAgICAgICAgICAgV3JpdGUtTG9nICJzd2l0Y2hpbmcgdG8gJHttb2RlfTogJChpZiAoJHJlYXNvbikgeyAkcmVhc29uIH0gZWxzZSB7ICdQQyBmcmVlIGZvciA1IG1pbicgfSkiCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgIH0gZWxzZWlmICgtbm90ICRsaXN0ZW5lcnMuQ291bnQgLWFuZCAtbm90ICRzZXJ2ZXJzLkNvdW50IC1hbmQgKCRzZXJ2aW5nID0gU2VydmluZykpIHsKICAgICAgICAgICAgICAgICMgVmVyaWZpY2F0aW9uIGNhbiB0YWtlIHNlY29uZHM7IGEgZ2FtZSBtYXkgaGF2ZSBzdGFydGVkIGR1cmluZyBoYXNoaW5nLgogICAgICAgICAgICAgICAgaWYgKFRyYWluaW5nKSB7IHRocm93ICdUcmFpbmluZyBzdGFydGVkIGR1cmluZyBtb2RlbCB2ZXJpZmljYXRpb247IGxhdW5jaCBkZWZlcnJlZCcgfQogICAgICAgICAgICAgICAgaWYgKCRtb2RlIC1lcSAnZnVsbCcgLWFuZCAoJGFnYWluID0gQnVzeSkpIHsKICAgICAgICAgICAgICAgICAgICAkbW9kZSA9IFBpY2tNb2RlICRhZ2FpbiAkbnVsbAogICAgICAgICAgICAgICAgICAgIGlmICgtbm90ICRtb2RlKSB7IHRocm93ICIkYWdhaW4gZHVyaW5nIG1vZGVsIHZlcmlmaWNhdGlvbjsgbGF1bmNoIGRlZmVycmVkIiB9CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkZ3B1ID0gIi0tbi1ncHUtbGF5ZXJzICRsYXllcnMiCiAgICAgICAgICAgICAgICAjIFNoYXJlZDogQ1BVIG9ubHkgKG5vIGxheWVycywgbm8gb3Agb2ZmbG9hZCksIDQgb2YgOCBjb3JlcywgbG93IHByaW9yaXR5LiAtLWZpdCBzaXplZCB0aGUgb2ZmbG9hZAogICAgICAgICAgICAgICAgIyBvbmNlIGF0IHRoZSBzdGFydCBhbmQgc3RpbGwgbGVmdCB0aGUgZ2FtZSA5OSBNaUIgYW5kIHRoZSBHUFUgYXQgMTAwICUgKDIwMjYtMTAtMTIpLgogICAgICAgICAgICAgICAgaWYgKCRtb2RlIC1lcSAnc2hhcmVkJykgeyAkZ3B1ID0gJy0tbi1ncHUtbGF5ZXJzIDAgLS1uby1vcC1vZmZsb2FkIC0tdGhyZWFkcyA0IC0tcHJpbyAtMScgfQogICAgICAgICAgICAgICAgJGVudjpMTEFNQV9BUkdfQ0hBVF9URU1QTEFURV9LV0FSR1MgPSAneyJlbmFibGVfdGhpbmtpbmciOmZhbHNlfScKICAgICAgICAgICAgICAgICRhcmd1bWVudHMgPSAiLS1tb2RlbCAkKCRzZXJ2aW5nLlBhdGgpIC0tYWxpYXMgJCgkc2VydmluZy5BbGlhcykgLS1ob3N0IDEyNy4wLjAuMSAtLXBvcnQgJHBvcnQgLS1qaW5qYSAtLWN0eC1zaXplIDgxOTIgLS1wYXJhbGxlbCAxICRncHUgLS10ZW1wIDAuNiAtLXRvcC1rIDIwIC0tdG9wLXAgMC45NSAtLW1pbi1wIDAgLS1yZXBlYXQtcGVuYWx0eSAxLjAiCiAgICAgICAgICAgICAgICAkc2VydmVyID0gU3RhcnQtUHJvY2VzcyAiJGJhc2VcbGxhbWFcbGxhbWEtc2VydmVyLmV4ZSIgLUFyZ3VtZW50TGlzdCAkYXJndW1lbnRzIC1Xb3JraW5nRGlyZWN0b3J5ICIkYmFzZVxsbGFtYSIgLVdpbmRvd1N0eWxlIEhpZGRlbiAtUGFzc1RocnUgLVJlZGlyZWN0U3RhbmRhcmRPdXRwdXQgIiRydW50aW1lXHdhdGNoLSRwb3J0Lm91dC5sb2ciIC1SZWRpcmVjdFN0YW5kYXJkRXJyb3IgIiRydW50aW1lXHdhdGNoLSRwb3J0LmVyci5sb2ciCiAgICAgICAgICAgICAgICAjIENyZWF0aW9uIHRpbWUgcHJldmVudHMgYSBzdGFsZSBQSUQgZmlsZSBmcm9tIGF1dGhvcml6aW5nIGEgcmV1c2VkIFBJRC4KICAgICAgICAgICAgICAgICRzdGFydGVkID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiUHJvY2Vzc0lkPSQoJHNlcnZlci5JZCkiCiAgICAgICAgICAgICAgICBAeyBQcm9jZXNzSWQgPSAkc2VydmVyLklkOyBDcmVhdGlvbkRhdGUgPSAkc3RhcnRlZC5DcmVhdGlvbkRhdGUuVG9TdHJpbmcoJ28nKSB9IHwgQ29udmVydFRvLUpzb24gfCBTZXQtQ29udGVudCAkcGlkRmlsZQogICAgICAgICAgICAgICAgV3JpdGUtTG9nICJzdGFydGVkIFBJRCAkKCRzZXJ2ZXIuSWQpICgkbW9kZSkiCiAgICAgICAgICAgIH0gZWxzZWlmICgtbm90ICRsaXN0ZW5lcnMuQ291bnQgLWFuZCAtbm90ICRzZXJ2ZXJzLkNvdW50KSB7CiAgICAgICAgICAgICAgICBpZiAoLW5vdCAkc2NyaXB0Om1vZGVsRmFpbHVyZUxvZ2dlZCkgeyBXcml0ZS1Mb2cgIm1vZGVsIG1pc3Npbmcgb3IgY2hlY2tzdW0gbWlzbWF0Y2g7IGluZmVyZW5jZSBkaXNhYmxlZCI7ICRzY3JpcHQ6bW9kZWxGYWlsdXJlTG9nZ2VkID0gJHRydWUgfQogICAgICAgICAgICB9CiAgICAgICAgfSBjYXRjaCB7IFdyaXRlLUxvZyAiZXJyb3I6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIiB9CiAgICAgICAgaWYgKC1ub3QgJE9uY2UpIHsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAoW01hdGhdOjpNYXgoMCwgMTUwMDAgLSBbaW50XSRjeWNsZS5FbGFwc2VkTWlsbGlzZWNvbmRzKSkgfQogICAgfSB3aGlsZSAoLW5vdCAkT25jZSkKfSBmaW5hbGx5IHsKICAgICRtdXRleC5SZWxlYXNlTXV0ZXgoKQogICAgJG11dGV4LkRpc3Bvc2UoKQp9Cg=='
    'busy.ps1' = 'IyBEb3Qtc291cmNlZCBieSB3YXRjaC5wczEgYW5kIHRyYWluXHJ1bi1ndWFyZGVkLnBzMTsgZXhwZWN0cyAkYmFzZSwgJFRlc3RQb3J0IGFuZCAkR3B1UGVyY2VudCBpbiB0aGUgY2FsbGVyJ3Mgc2NvcGUuCkFkZC1UeXBlIEAnCnVzaW5nIFN5c3RlbTsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwpwdWJsaWMgc3RhdGljIGNsYXNzIEJhbmRpdFdpbmRvdyB7CiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldIHB1YmxpYyBzdHJ1Y3QgUmVjdCB7IHB1YmxpYyBpbnQgTGVmdCwgVG9wLCBSaWdodCwgQm90dG9tOyB9CiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdWludCBXVFNHZXRBY3RpdmVDb25zb2xlU2Vzc2lvbklkKCk7CiAgICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIEludFB0ciBHZXRGb3JlZ3JvdW5kV2luZG93KCk7CiAgICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIEludFB0ciBHZXRTaGVsbFdpbmRvdygpOwogICAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiB1aW50IEdldFdpbmRvd1RocmVhZFByb2Nlc3NJZChJbnRQdHIgaCwgb3V0IHVpbnQgcGlkKTsKICAgIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gYm9vbCBHZXRXaW5kb3dSZWN0KEludFB0ciBoLCBvdXQgUmVjdCByKTsKICAgIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gSW50UHRyIE1vbml0b3JGcm9tV2luZG93KEludFB0ciBoLCB1aW50IGZsYWdzKTsKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsKV0gcHVibGljIHN0cnVjdCBNb25pdG9yIHsgcHVibGljIGludCBTaXplOyBwdWJsaWMgUmVjdCBCb3VuZHMsIFdvcms7IHB1YmxpYyB1aW50IEZsYWdzOyB9CiAgICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgR2V0TW9uaXRvckluZm8oSW50UHRyIGgsIHJlZiBNb25pdG9yIG0pOwogICAgcHVibGljIHN0YXRpYyB1aW50IEZvcmVncm91bmRQaWQoKSB7IHVpbnQgcGlkOyBHZXRXaW5kb3dUaHJlYWRQcm9jZXNzSWQoR2V0Rm9yZWdyb3VuZFdpbmRvdygpLCBvdXQgcGlkKTsgcmV0dXJuIHBpZDsgfQogICAgcHVibGljIHN0YXRpYyBib29sIEZ1bGxzY3JlZW4oKSB7CiAgICAgICAgdmFyIGggPSBHZXRGb3JlZ3JvdW5kV2luZG93KCk7CiAgICAgICAgaWYgKGggPT0gSW50UHRyLlplcm8gfHwgaCA9PSBHZXRTaGVsbFdpbmRvdygpKSByZXR1cm4gZmFsc2U7CiAgICAgICAgUmVjdCByOyB2YXIgbSA9IG5ldyBNb25pdG9yKCk7IG0uU2l6ZSA9IE1hcnNoYWwuU2l6ZU9mKG0pOwogICAgICAgIGlmICghR2V0V2luZG93UmVjdChoLCBvdXQgcikgfHwgIUdldE1vbml0b3JJbmZvKE1vbml0b3JGcm9tV2luZG93KGgsIDIpLCByZWYgbSkpIHRocm93IG5ldyBFeGNlcHRpb24oIldpbmRvdyBwcm9iZSBmYWlsZWQiKTsKICAgICAgICByZXR1cm4gci5MZWZ0IDw9IG0uQm91bmRzLkxlZnQgJiYgci5Ub3AgPD0gbS5Cb3VuZHMuVG9wICYmIHIuUmlnaHQgPj0gbS5Cb3VuZHMuUmlnaHQgJiYgci5Cb3R0b20gPj0gbS5Cb3VuZHMuQm90dG9tOwogICAgfQp9CidACmZ1bmN0aW9uIEJ1c3kgewogICAgIyAtUmVtb3RlOiBjYWxsZXIgcnVucyBvdXRzaWRlIHRoZSBpbnRlcmFjdGl2ZSBzZXNzaW9uIChzc2gpOiBza2lwIHRoZSBjb25zb2xlLXNlc3Npb24gYW5kCiAgICAjIGZ1bGxzY3JlZW4gcHJvYmVzLCB3aGljaCBvbmx5IG1ha2Ugc2Vuc2UgdGhlcmUuIC1JZ25vcmVQaWRzOiBjYWxsZXIncyBvd24gR1BVIHVzZXJzLgogICAgcGFyYW0oW2ludFtdXSRJZ25vcmVQaWRzID0gQCgpLCBbc3dpdGNoXSRSZW1vdGUpCiAgICBpZiAoLW5vdCAkUmVtb3RlIC1hbmQgLW5vdCAkVGVzdFBvcnQgLWFuZCBbQmFuZGl0V2luZG93XTo6V1RTR2V0QWN0aXZlQ29uc29sZVNlc3Npb25JZCgpIC1uZSAoR2V0LVByb2Nlc3MgLUlkICRQSUQpLlNlc3Npb25JZCkgeyByZXR1cm4gJ2Fub3RoZXIgY29uc29sZSBzZXNzaW9uIChvciBubyBjb25zb2xlKScgfQogICAgIyBMaWdodCBnYW1lcyBuZXZlciBjb3VudCBhcyBnYW1lcyBhbmQgZG8gbm90IHRyaWdnZXIgdGhlIGZ1bGxzY3JlZW4gcnVsZSB3aGlsZSBmb2N1c2VkLgogICAgJGxpZ2h0ID0gQCgnaXNhYWMtbmcuZXhlJywgJ2lzYWFjLmV4ZScsICd3YWxscGFwZXI2NC5leGUnLCAnd2FsbHBhcGVyMzIuZXhlJywgJ2Nocm9tZS5leGUnLCAnbXNlZGdlLmV4ZScsICdmaXJlZm94LmV4ZScsICdicmF2ZS5leGUnLCAndmxjLmV4ZScpCiAgICBpZiAoVGVzdC1QYXRoICIkYmFzZVxsaWdodC1nYW1lcy50eHQiKSB7CiAgICAgICAgJGxpZ2h0ICs9IEAoR2V0LUNvbnRlbnQgIiRiYXNlXGxpZ2h0LWdhbWVzLnR4dCIgfCBGb3JFYWNoLU9iamVjdCB7ICRfLlRyaW0oKSB9IHwgV2hlcmUtT2JqZWN0IHsgJF8gLWFuZCAtbm90ICRfLlN0YXJ0c1dpdGgoJyMnKSB9KQogICAgfQogICAgJGxpZ2h0Rm9yZWdyb3VuZCA9ICRmYWxzZQogICAgaWYgKC1ub3QgJFJlbW90ZSkgewogICAgICAgICRmb3JlZ3JvdW5kID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgLUZpbHRlciAiUHJvY2Vzc0lkPSQoW0JhbmRpdFdpbmRvd106OkZvcmVncm91bmRQaWQoKSkiCiAgICAgICAgJGxpZ2h0Rm9yZWdyb3VuZCA9ICRudWxsIC1uZSAkZm9yZWdyb3VuZCAtYW5kICRsaWdodCAtY29udGFpbnMgJGZvcmVncm91bmQuTmFtZQogICAgICAgIGlmICgtbm90ICRsaWdodEZvcmVncm91bmQgLWFuZCBbQmFuZGl0V2luZG93XTo6RnVsbHNjcmVlbigpKSB7IHJldHVybiAnZnVsbHNjcmVlbiB3aW5kb3cnIH0KICAgIH0KICAgICRnYW1lcyA9IEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgfCBXaGVyZS1PYmplY3QgewogICAgICAgICRfLk5hbWUgLW5vdGluICRsaWdodCAtYW5kICgKICAgICAgICAgICAgJF8uTmFtZSAtbWF0Y2ggJ14oTWluZWNyYWZ0fGphdmF3fFJvYmxveFBsYXllckJldGF8Rm9ydG5pdGVDbGllbnQtV2luNjQtU2hpcHBpbmd8VkFMT1JBTlQtV2luNjQtU2hpcHBpbmd8Y3MyfEdUQTV8Um9ja2V0TGVhZ3VlKVwuZXhlJCcgLW9yCiAgICAgICAgICAgICRfLkV4ZWN1dGFibGVQYXRoIC1tYXRjaCAnXFwoc3RlYW1hcHBzXFxjb21tb258RXBpYyBHYW1lc3xSaW90IEdhbWVzKVxcJwogICAgICAgICkKICAgIH0pCiAgICBpZiAoJGdhbWVzLkNvdW50KSB7IHJldHVybiAiZ2FtZSAkKCRnYW1lc1swXS5OYW1lKSIgfQogICAgaWYgKCRudWxsIC1uZSAkR3B1UGVyY2VudCkgeyAkdXNhZ2UgPSAkR3B1UGVyY2VudCB9CiAgICBlbHNlIHsKICAgICAgICAkbGxhbWEgPSBAKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIk5hbWU9J2xsYW1hLXNlcnZlci5leGUnIiB8IEZvckVhY2gtT2JqZWN0IFByb2Nlc3NJZCkKICAgICAgICAjIExpZ2h0IGdhbWVzIChNaW5lY3JhZnQsIElzYWFjLCBicm93c2VycykgbWF5IHVzZSB0aGUgR1BVIG5leHQgdG8gQW5keTogdGhlaXIgbG9hZCBkb2VzIG5vdCBjb3VudCBlaXRoZXIuCiAgICAgICAgJGxsYW1hICs9IEAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX1Byb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkbGlnaHQgLWNvbnRhaW5zICRfLk5hbWUgfSB8IEZvckVhY2gtT2JqZWN0IFByb2Nlc3NJZCkKICAgICAgICAkY291bnRlcnMgPSBAKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9QZXJmRm9ybWF0dGVkRGF0YV9HUFVQZXJmb3JtYW5jZUNvdW50ZXJzX0dQVUVuZ2luZSkKICAgICAgICBpZiAoLW5vdCAkY291bnRlcnMuQ291bnQpIHsgdGhyb3cgJ05vIEdQVSBlbmdpbmUgY291bnRlcnM7IHJlZnVzaW5nIGluZmVyZW5jZScgfQogICAgICAgICRlbmdpbmVzID0gQHt9CiAgICAgICAgZm9yZWFjaCAoJGNvdW50ZXIgaW4gJGNvdW50ZXJzKSB7CiAgICAgICAgICAgIGlmICgkY291bnRlci5OYW1lIC1ub3RtYXRjaCAnXnBpZF8oXGQrKV8oLispJCcpIHsgdGhyb3cgJ1VucmVjb2duaXplZCBHUFUgY291bnRlcicgfQogICAgICAgICAgICBpZiAoJGxsYW1hIC1jb250YWlucyBbaW50XSRNYXRjaGVzWzFdIC1vciAkSWdub3JlUGlkcyAtY29udGFpbnMgW2ludF0kTWF0Y2hlc1sxXSkgeyBjb250aW51ZSB9CiAgICAgICAgICAgICRlbmdpbmUgPSAkTWF0Y2hlc1syXQogICAgICAgICAgICAkZW5naW5lc1skZW5naW5lXSArPSBbaW50XSRjb3VudGVyLlV0aWxpemF0aW9uUGVyY2VudGFnZQogICAgICAgIH0KICAgICAgICAkdXNhZ2UgPSAoJGVuZ2luZXMuVmFsdWVzIHwgTWVhc3VyZS1PYmplY3QgLU1heGltdW0pLk1heGltdW0KICAgIH0KICAgIGlmICgkdXNhZ2UgLWdlIDIwKSB7IHJldHVybiAibm9uLWxsYW1hIEdQVSAkdXNhZ2UlIiB9CiAgICByZXR1cm4gJG51bGwKfQo='
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
