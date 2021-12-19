Shader "zznewclear13/BasicGGXBRDFShader"
{
    Properties
    {
        _BaseColor ("Base Color", color) = (1, 1, 1, 1)
        _BaseMap("Base Map", 2D) = "white" {}

        _BumpMap ("Bump Map", 2D) = "bump" {}
        _BumpIntensity ("Bump Intensity", range(0, 1)) = 1
        _RoughnessMap("Roughness Map", 2D) = "white" {}
        _RoughnessIntensity ("Roughness Intensity", range(0, 1)) = 1
        _MetallicMap ("Metallic Map", 2D) = "black" {}
        _MetallicIntensity ("Metallic Intensity", range(0, 1)) = 1
        _OcclusionMap("Occlusion Map", 2D) = "white" {}
        _OcclusionIntensity("Occlusion Intensity", range(0, 1)) = 1
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    
    sampler2D _BaseMap;
    sampler2D _BumpMap;
    sampler2D _RoughnessMap;
    sampler2D _MetallicMap;
    sampler2D _OcclusionMap;
    CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;
    float4 _BaseMap_ST;
    float _BumpIntensity;
    float _RoughnessIntensity;
    float _MetallicIntensity;
    float _OcclusionIntensity;
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

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK       
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #pragma multi_compile _ LIGHTMAP_ON

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
                float a2 = roughness * roughness;
                float d = max(1e-16, ndoth * ndoth * (a2 - 1) + 1);
                return a2 * rcp(d * d);
            }

            float G(float ndotl, float ndotv, float roughness)
            {
                float a2 = roughness * roughness;
                float gv = ndotv * sqrt((ndotl - a2 * ndotl) * ndotl + a2);
                float gl = ndotl * sqrt((ndotv - a2 * ndotv) * ndotl + a2);
                return 0.5 * rcp(gv + gl);
            }

            float3 F(float3 specular, float hdotl)
            {
                return specular + (1 - specular) * pow(1 - hdotl, 5);
            }

            float3 GGXBRDF(float3 wi, float3 wo, float3 normal, float3 specular, float roughness)
            {
                float3 h = normalize(wi + wo);
                float ndotv = abs(dot(normal, wo)) + 1e-5;
                float ndoth = max(dot(normal, h), 0.0);
                float ndotl = max(dot(normal, wi), 0.0);
                float hdotl = max(dot(h, wi), 0.0);

                float d = D(ndoth, roughness);
                float g = G(ndotl, ndotv, roughness);
                float3 f = F(specular, hdotl);

                return d * g * f;
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
                output.tangentWS = float4(normalInput.tangentWS, input.tangentOS.w);
                output.shadowCoord = TransformWorldToShadowCoord(vertexInput.positionWS);
                
                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
                OUTPUT_SH(normalInput.normalWS.xyz, output.vertexSH);

                return output;
            }

            float4 LitPassFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                //wo
                float3 positionWS = input.positionWS;
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
                
                //wi
                float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
                float4 shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                Light mainLight = GetMainLight(shadowCoord, positionWS, shadowMask);

                //normal
                float3 normalMap = UnpackNormal(tex2D(_BumpMap, input.uv));
                normalMap.xy *= _BumpIntensity;
                float3 bitangentWS = cross(input.normalWS, input.tangentWS.xyz) * input.tangentWS.w;
                float3x3 tbn = float3x3(normalize(input.tangentWS.xyz), normalize(bitangentWS), normalize(input.normalWS));
                float3 normalWS = mul(normalMap, tbn);

                //material properties
                float4 baseMap = tex2D(_BaseMap, input.uv);
                float roughnessMap = tex2D(_RoughnessMap, input.uv).r;
                float roughness = max(roughnessMap * _RoughnessIntensity, 1e-2);
                float metallicMap = tex2D(_MetallicMap, input.uv).r;
                float metallic = metallicMap * _MetallicIntensity;
                float occlusionMap = tex2D(_OcclusionMap, input.uv).r;
                float occlusion = occlusionMap * _OcclusionIntensity;

                float oneMinusReflectivity = kDieletricSpec.a * (1 - metallic);
                float reflectivity = 1.0 - oneMinusReflectivity;
                float3 diffuse = baseMap.rgb * oneMinusReflectivity;
                float3 specular = lerp(kDieletricSpec.rgb, baseMap.rgb, metallic);     
                
                //gi
                float3 bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, normalWS);
                MixRealtimeAndBakedGI(mainLight, normalWS, bakedGI);
                float3 giDiffuse = bakedGI;
                float3 reflectVector = reflect(-viewDirWS, normalWS);
                float3 giSpecular = GlossyEnvironmentReflection(reflectVector, roughness, 1.0);

                //directional lights
                float3 directDiffuse = diffuse;
                float3 directSpecular = GGXBRDF(mainLight.direction, viewDirWS, normalWS, specular, roughness);
                float ndotl = saturate(dot(mainLight.direction, normalWS));
                float atten = mainLight.shadowAttenuation;

                //indirectional lights
                float3 indirectDiffse = giDiffuse * diffuse;
                float surfaceReduction = rcp(roughness * roughness + 1.0);
                float grazingTerm = saturate(1.0 - roughness + reflectivity);
                float ndotv = saturate(dot(normalWS, viewDirWS));
                float fresnelTerm = pow(1.0 - ndotv, 5.0);
                float3 indirectSpecular = giSpecular * surfaceReduction * lerp(specular, grazingTerm, fresnelTerm);

                //final compose
                float3 directBRDF = (directDiffuse + directSpecular) * mainLight.color * atten * ndotl;//(directSpecular + directDiffuse) * mainLight.color * atten * ndotl;
                float3 indirectBRDF = indirectDiffse + indirectSpecular;

                float3 finalColor = (directBRDF + indirectBRDF) * occlusion;
                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float4 positionCS   : SV_POSITION;
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
                float4 position     : POSITION;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float4 positionCS   : SV_POSITION;
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
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv0          : TEXCOORD0;
                float2 uv1          : TEXCOORD1;
                float2 uv2          : TEXCOORD2;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
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
                float4 baseMap = tex2D(_BaseMap, input.uv);
                float roughnessMap = tex2D(_RoughnessMap, input.uv).r;
                float roughness = max(roughnessMap * _RoughnessIntensity, 1e-2);
                float metallicMap = tex2D(_MetallicMap, input.uv).r;
                float metallic = metallicMap * _MetallicIntensity;

                float oneMinusReflectivity = kDieletricSpec.a * (1 - metallic);
                float reflectivity = 1.0 - oneMinusReflectivity;
                float3 diffuse = baseMap.rgb * oneMinusReflectivity;
                float3 specular = lerp(kDieletricSpec.rgb, baseMap.rgb, metallic);

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
