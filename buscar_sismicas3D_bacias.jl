using GeoStats
using GeoIO
using GeoInterface
using DataFrames
using LibGEOS

# ---------------------------------------------------
# 1. Carregar shapefiles e criar DataFrames
# ---------------------------------------------------
bacias = GeoIO.load("data_ANP/bacias_gishub_db.shp")
s3d   = GeoIO.load("data_ANP/SISMICA_3D.shp")

bacias_df = DataFrame(bacias)
s3d_df   = DataFrame(s3d)

# ---------------------------------------------------
# 2. Funções para converter geometria (sem alterações)
# ---------------------------------------------------
function multipolygon_to_wkt(geom)
    primeiro_poligono = GeoInterface.getgeom(geom, 1)
    rings = GeoInterface.coordinates(primeiro_poligono)
    outer_ring = rings[1]
    points = [(float(p[1]), float(p[2])) for p in outer_ring]
    if !isempty(points) && points[1] != points[end]
        push!(points, points[1])
    end
    coord_str = join(["$(x) $(y)" for (x, y) in points], ", ")
    return "POLYGON(($coord_str))"
end

# ---------------------------------------------------
# 3. Nova função otimizada para filtrar sísmicas
# ---------------------------------------------------
function sismicas_na_bacia_otimizado(bacia_df::DataFrame, s3d_df::DataFrame, nome_bacia::String)
    # Passo 1: Encontrar a bacia de interesse ANTES de qualquer conversão
    idx = findfirst(bacias_df.name .== nome_bacia)
    if idx === nothing
        error("Sísmica '$nome_bacia' não encontrada")
    end
    
    bacia_original = bacia_df[idx, :]

    # Passo 2: Converter a geometria APENAS da bacia de interesse
    bacia_geom_wkt = multipolygon_to_wkt(bacia_original.geometry)
    bacia_geom_libgeos = LibGEOS.readgeom(bacia_geom_wkt)

    # Passo 3: Iterar pelas sísmicas, convertendo e verificando um a um
    indices_das_sismicas_dentro = Int[]
    for (i, sismica) in enumerate(eachrow(s3d_df))
        sismica_geom_wkt = multipolygon_to_wkt(sismica.geometry)
        sismica_geom_libgeos = LibGEOS.readgeom(sismica_geom_wkt)
        
        if LibGEOS.intersects(sismica_geom_libgeos, bacia_geom_libgeos)
            push!(indices_das_sismicas_dentro, i)
        end
    end

    # Passo 4: Retornar um novo DataFrame apenas com as sísmicas encontradas
    return s3d_df[indices_das_sismicas_dentro, :]
end

# ---------------------------------------------------
# 4. Exemplo de uso
# ---------------------------------------------------
println("Bacias disponíveis:")
println(unique(bacias_df.name))

# Defina a sísmica de interesse aqui
nome_bacia = "Santos"

# Chamar a nova função otimizada
sismicas_dentro_df = sismicas_na_bacia_otimizado(bacias_df, s3d_df, nome_bacia)

# ---------------------------------------------------
# 5. Visualizar Resultados
# ---------------------------------------------------
if !isempty(sismicas_dentro_df)
    println("\nSísmicas encontradas dentro da bacia '$nome_sismica':")

    visualizacao_completa_df = select(sismicas_dentro_df, 
        :PROJETO,
        :TIPO_PROC, 
        :CONF, 
        :BLOCO,
        :CAMPO
    )

    println(visualizacao_completa_df)
else
    println("\nNenhuma sísmica encontrada dentro da bacia '$nome_bacia'.")
end