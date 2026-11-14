// Route Defense — import settings: crisp pixel art (point filter, no compression, no mipmaps), big sprite sheets allowed,
// tilesets readable (the game copies their pixels to build each random map), music streamed.
using UnityEditor;
using UnityEngine;

namespace RouteDefense.EditorTools
{
    public class RDImport : AssetPostprocessor
    {
        const string ROOT = "Assets/RouteDefense/Resources/";
        void OnPreprocessTexture()
        {
            if (!assetPath.StartsWith(ROOT)) return;
            var ti = (TextureImporter)assetImporter;
            ti.textureType = TextureImporterType.Default;
            ti.isReadable = assetPath.StartsWith(ROOT + "Ts/");
            ti.filterMode = FilterMode.Point; ti.wrapMode = TextureWrapMode.Clamp;
            ti.mipmapEnabled = false; ti.npotScale = TextureImporterNPOTScale.None; ti.alphaIsTransparency = true;
            ti.textureCompression = TextureImporterCompression.Uncompressed; ti.maxTextureSize = 8192;
            foreach (var p in new[] { "Android", "Standalone" })
            {
                var s = ti.GetPlatformTextureSettings(p); s.overridden = true; s.maxTextureSize = 8192; s.format = TextureImporterFormat.RGBA32; s.textureCompression = TextureImporterCompression.Uncompressed;
                ti.SetPlatformTextureSettings(s);
            }
        }
        void OnPreprocessAudio()
        {
            if (!assetPath.StartsWith(ROOT)) return;
            var ai = (AudioImporter)assetImporter; bool music = !System.IO.Path.GetFileName(assetPath).StartsWith("s");
            var s = ai.defaultSampleSettings;
            s.loadType = music ? AudioClipLoadType.Streaming : AudioClipLoadType.DecompressOnLoad;
            s.compressionFormat = AudioCompressionFormat.Vorbis; s.quality = 0.5f;
            ai.defaultSampleSettings = s; ai.forceToMono = true;
        }
    }
}
