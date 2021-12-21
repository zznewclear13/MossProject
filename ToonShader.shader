Shader "zznewclear13/ToonShader"
{
    Properties
    {
        [Header(Platform Setting)]
        [Toggle(PLATFORM_PC)] _PlatformPC ("Platform PC", float) = 1

        [Header(Basic Material Properties)]
        _BaseColor("Base Color", color) = (1, 1, 1, 1)
        _BaseMap("Base Map", 2D) = "white" {}
        _BumpMap("Bump Map", 2D) = "bump" {}
        _BumpIntensity("Bump Intensity", range(0, 1)) = 1
        _RoughnessMap("Roughness Map", 2D) = "white" {}
        _RoughnessIntensity("Roughness Intensity", range(0, 1)) = 1
        _MetallicIntensity("Metallic Intensity", range(0, 1)) = 1

        [Header(Fuzz Properties)]
        _FuzzColor("Fuzz Color", color) = (1, 1, 1, 1)
        _FuzzMap("Fuzz Map", 2D) = "black" {}
        _FuzzIntensity("Fuzz Intensity", range(0, 1)) = 1
        _ScatterDensity("Scattering Density", range(0, 0.2)) = 0.1

        [Header(Decal Properties)]
        [Toggle(ENABLE_DECAL)] _EnableDecal ("Enable Decal", float) = 1
        _DecalColor ("Decal Color", color) = (1, 1, 1, 1)
        _DecalMap("Decal Map", 2D) = "black" {}
        _DecalHeight("Decal Height", float) = 20
        _DecalBumpMap("Decal Bump Map", 2D) = "bump" {}
        _DecalBumpIntensity("Decal Bump Intensiy", range(0, 1)) = 1
        _DecalRoughnessMap ("Decal Roughness map", 2D) = "white" {}
        _DecalRoughnessIntensity ("Decal Roughness Intensity", range(0, 1)) = 1
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    sampler2D _BaseMap;
    sampler2D _BumpMap;
    sampler2D _RoughnessMap;
    sampler2D _FuzzMap;
    sampler2D _DecalMap;
    sampler2D _DecalBumpMap;
    sampler2D _DecalRoughnessMap;

    CBUFFER_START(UnityPerMaterial)
        half4 _BaseColor;
        half4 _BaseMap_ST;
        half _BumpIntensity;
        half _RoughnessIntensity;
        half _MetallicIntensity;

        half4 _FuzzColor;
        half _FuzzIntensity;
        half _ScatterDensity;

        half4 _DecalColor;
        half4 _DecalMap_TexelSize;
        half4 _DecalMap_ST;
        half _DecalHeight;
        half _DecalBumpIntensity;
        half _DecalRoughnessIntensity;
    CBUFFER_END

    ENDHLSL

    SubShader
    {
        Tags{ "RenderType" = "Opaque"}
        Pass
        {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #pragma shader_feature_local _NORMALMAP

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK       
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_ON

            #pragma multi_compile _ PLATFORM_PC
            #pragma multi_compile _ ENABLE_DECAL

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            struct Attributes
            {
                float4 positionOS           : POSITION;
                float3 normalOS             : NORMAL;
                float4 tangentOS            : TANGENT;
                float2 texcoord             : TEXCOORD0;
                float2 staticLightmapUV     : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                float2 uv                       : TEXCOORD0;
                float3 positionWS               : TEXCOORD1;
                float3 normalWS                 : TEXCOORD2;
                float4 tangentWS                : TEXCOORD3;
                float4 shadowCoord              : TEXCOORD4;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 5);

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float D(float ndoth, float roughness)
            {
                float a = ndoth * roughness;
                float k = roughness / (1.0 - ndoth * ndoth + a * a);
                return k * k;
            }

            float G(float ndotl, float ndotv, float roughness)
            {
                float a2 = roughness * roughness;
                float gv = ndotv * sqrt((1.0 - a2) * ndotl * ndotl + a2);
                float gl = ndotl * sqrt((1.0 - a2) * ndotv * ndotv + a2);
                return 0.5 * rcp(gv + gl);
            }

            float3 F(float3 specular, float hdotl)
            {
                return specular + (1 - specular) * pow(1 - hdotl, 5);
            }

            float3 GGXBRDF(float3 wi, float3 wo, float3 normal, float3 specular, float roughness)
            {
                float3 h = normalize(wi + wo);
                float ndotv = max(dot(normal, wo), 1e-5);
                float ndoth = max(dot(normal, h), 0.0);
                float ndotl = max(dot(normal, wi), 0.0);
                float hdotl = max(dot(h, wi), 0.0);

                float d = D(ndoth, roughness);
                float g = G(ndotl, ndotv, roughness);
                float3 f = F(specular, hdotl);

                return d * g * f;
            }

            //[Samurai Shading in Ghost of Tsuma](https://blog.selfshadow.com/publications/s2020-shading-course/patry/slides/index.html)
            half GScatter(half ndotv, half ndotl, half scatterDensity)
            {
                return ndotl * (1.0 - exp(-scatterDensity * (ndotl + ndotv) / (ndotl * ndotv))) / (ndotl + ndotv);
            }

            //Extension to energy-conserving wrapped diffuse, Steve McAuley
            half SoftenNdotL(half ndotl)
            {
                half val = (ndotl + 0.2) / 1.2;
                return 1.25 * val * val;
            }

            Varyings LitPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = half4(normalInput.tangentWS, input.tangentOS.w);
                output.shadowCoord = TransformWorldToShadowCoord(vertexInput.positionWS);

                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
                OUTPUT_SH(normalInput.normalWS.xyz, output.vertexSH);

                return output;
            }

            half4 LitPassFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                //wo
                half3 positionWS = input.positionWS;
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);

                //wi
                half4 shadowCoord = TransformWorldToShadowCoord(positionWS);
                half4 shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                Light mainLight = GetMainLight(shadowCoord, positionWS, shadowMask);

                //tangent bitangent normal matrix
                half3 bitangentWS = cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w;
                half3x3 tbn = half3x3(input.tangentWS.xyz, bitangentWS, input.normalWS);
#if PLATFORM_PC && ENABLE_DECAL
                half3 lightDirTS = mul(tbn, mainLight.direction);
                lightDirTS.xy *= rcp(max(lightDirTS.z, 0.5));
                half2 decalOffset = _DecalMap_TexelSize.xy * lightDirTS.xy;
                half2 decalUV = input.uv * _DecalMap_ST.xy + _DecalMap_ST.zw;
                half4 decalMap = tex2D(_DecalMap, decalUV) * _DecalColor;
#endif

                //normal
                half3 normalMap = UnpackNormal(tex2D(_BumpMap, input.uv));
#if PLATFORM_PC && ENABLE_DECAL
                half3 decalNormalMap = UnpackNormal(tex2D(_DecalBumpMap, decalUV));
                half2 normalXY = lerp(normalMap.xy * _BumpIntensity, decalNormalMap.xy * _DecalBumpIntensity, decalMap.a);
#else
                half2 normalXY = normalMap.xy * _BumpIntensity;
#endif
                normalMap = normalize(half3(normalXY, 1.0));
                half3 normalWS = mul(normalMap, tbn);
                normalWS = normalize(normalWS);

                //material properties
                half metallic =  _MetallicIntensity;
                half4 baseMap = tex2D(_BaseMap, input.uv) * _BaseColor;
#if PLATFORM_PC
                half roughnessMap = tex2D(_RoughnessMap, input.uv).r;
                half roughness = max(roughnessMap * _RoughnessIntensity, 1e-2);
#endif
                half fuzzMap = tex2D(_FuzzMap, input.uv).r;
                half fuzziness = fuzzMap * _FuzzIntensity;

#if PLATFORM_PC && ENABLE_DECAL
                baseMap.rgb = lerp(baseMap.rgb, decalMap.rgb, decalMap.a);

                half decalRoughnessMap = tex2D(_DecalRoughnessMap, decalUV).r;
                half decalRoughness = max(decalRoughnessMap * _DecalRoughnessIntensity, 1e-2);
                roughness = lerp(roughness, decalRoughness, decalMap.a);
                
                half decalShadow = tex2D(_DecalMap, decalUV + decalOffset * _DecalHeight).a;
                decalShadow = max(decalMap.a, 1 - decalShadow);

                fuzziness *= (1.0 - decalMap.a);
#endif

                //f90, f0
                half oneMinusReflectivity = kDieletricSpec.a * (1 - metallic);
                half reflectivity = 1.0 - oneMinusReflectivity;
                half3 diffuse = baseMap.rgb * oneMinusReflectivity;
                half3 specular = lerp(kDieletricSpec.rgb, baseMap.rgb, metallic);

                //gi
                half3 bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, normalWS);
                MixRealtimeAndBakedGI(mainLight, normalWS, bakedGI);
                half3 giDiffuse = bakedGI;
                half3 reflectVector = reflect(-viewDirWS, normalWS);
#if PLATFORM_PC
                half3 giSpecular = GlossyEnvironmentReflection(reflectVector, roughness, 1.0);
#endif

                //directional lights
                half ndotl = dot(normalWS, mainLight.direction);
                half softNdotL = SoftenNdotL(ndotl);
                ndotl = max(ndotl, 0.0);
                half ndotv = max(dot(normalWS, viewDirWS), 1e-4);
                half atten = mainLight.shadowAttenuation;
#if PLATFORM_PC && ENABLE_DECAL
                atten *= decalShadow;
#endif
                //Fuzz Diffuse Functions
                half gScatter = GScatter(ndotv, softNdotL, _ScatterDensity);
                half3 directDiffuse = diffuse * mainLight.color * atten * lerp(ndotl, _FuzzColor * gScatter * 5.0 * softNdotL, fuzziness);
#if PLATFORM_PC
                half tempRoughness = lerp(roughness, 1.0, fuzziness);
                half3 directSpecular = GGXBRDF(mainLight.direction, viewDirWS, normalWS, specular, tempRoughness);
#endif

                //indirectional lights
                half indirectionalScatter = GScatter(ndotv, 1.0, _ScatterDensity);
                half3 indirectDiffse = giDiffuse * diffuse * lerp(1.0, _FuzzColor * indirectionalScatter * 5.0, fuzziness);
#if PLATFORM_PC
                half surfaceReduction = rcp(tempRoughness * tempRoughness + 1.0);
                half grazingTerm = saturate(1.0 - tempRoughness + reflectivity);
                half fresnelTerm = pow(1.0 - ndotv, 5.0);
                half3 indirectSpecular = giSpecular * surfaceReduction * lerp(specular, grazingTerm, fresnelTerm);
#endif

                //final compose
                half3 directBRDF = directDiffuse;
                half3 indirectBRDF = indirectDiffse;
#if PLATFORM_PC
                directBRDF += directSpecular * mainLight.color * atten * ndotl;
                indirectBRDF += indirectSpecular;
#endif
                half3 finalColor = directBRDF + indirectBRDF;

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags{ "LightMode" = "ShadowCaster" }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            half3 _LightDirection;

            struct Attributes
            {
                half4 positionOS   : POSITION;
                half3 normalOS     : NORMAL;
                half4 tangentOS    : TANGENT;
                half2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                half2 uv           : TEXCOORD0;
                half4 positionCS   : SV_POSITION;
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(vertexInput.positionWS, normalInput.normalWS, _LightDirection));
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0.0;
            }

            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            struct Attributes
            {
                half4 position     : POSITION;
                half2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                half2 uv           : TEXCOORD0;
                half4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionCS = TransformObjectToHClip(input.position.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                return 0.0;
            }

            ENDHLSL
        }

        Pass
        {
            Name "Meta"
            Tags{"LightMode" = "Meta"}

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"

            #pragma vertex MetaVertex
            #pragma fragment MetaFragment

            struct Attributes
            {
                half4 positionOS   : POSITION;
                half3 normalOS     : NORMAL;
                half2 uv0          : TEXCOORD0;
                half2 uv1          : TEXCOORD1;
                half2 uv2          : TEXCOORD2;
            };

            struct Varyings
            {
                half4 positionCS   : SV_POSITION;
                half2 uv           : TEXCOORD0;
            };

            Varyings MetaVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = MetaVertexPosition(input.positionOS, input.uv1, input.uv2, unity_LightmapST, unity_DynamicLightmapST);
                output.uv = TRANSFORM_TEX(input.uv0, _BaseMap);
                return output;
            }

            half4 MetaFragment(Varyings input) : SV_Target
            {
                //material properties
                half4 baseMap = tex2D(_BaseMap, input.uv);
                half roughnessMap = tex2D(_RoughnessMap, input.uv).r;
                half roughness = max(roughnessMap * _RoughnessIntensity, 1e-2);
                half metallic = _MetallicIntensity;

                half oneMinusReflectivity = kDieletricSpec.a * (1 - metallic);
                half reflectivity = 1.0 - oneMinusReflectivity;
                half3 diffuse = baseMap.rgb * oneMinusReflectivity;
                half3 specular = lerp(kDieletricSpec.rgb, baseMap.rgb, metallic);

                MetaInput metaInput;
                metaInput.Albedo = diffuse;
                metaInput.SpecularColor = specular;
                metaInput.Emission = 0;
                return MetaFragment(metaInput);
            }

            ENDHLSL
        }
    }
}
