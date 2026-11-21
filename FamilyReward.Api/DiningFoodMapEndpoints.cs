using System.Text.Json;
using Npgsql;

internal static class DiningFoodMapEndpoints
{
    private sealed record Center(Guid Id, string? Name, double Latitude, double Longitude, string? CoordinateSystem);
    private sealed record Place(Guid Id, string? Name, string? Category, string? LocationText,
        double Latitude, double Longitude, string? CoordinateSystem, string? Description);
    private sealed record Review(int Stars, string? Note);
    private const string Membership = """
        EXISTS (SELECT 1 FROM dining_food_map_follows f WHERE f.map_id=m.id AND f.user_id=@owner)
        """;
    private const string Distance = """
        12742000 * asin(sqrt(least(1,
          power(sin(radians(latitude-@lat)/2),2) +
          cos(radians(latitude))*cos(radians(@lat))*power(sin(radians(longitude-@lon)/2),2))))
        """;

    public static void MapDiningFoodMaps(this WebApplication app, string cs, Func<HttpRequest, string?> ownerFor)
    {
        var group = app.MapGroup("/api/dining/food-maps").RequireAuthorization();
        group.AddEndpointFilter(async (context, next) =>
        {
            context.HttpContext.Response.Headers.CacheControl = "private, no-store";
            return ownerFor(context.HttpContext.Request) is null ? Results.Unauthorized() : await next(context);
        });
        group.MapGet("/", (string? query, double? latitude, double? longitude, bool? followed, string? coordinateSystem, HttpRequest r, CancellationToken ct) =>
        {
            if (latitude.HasValue != longitude.HasValue || (latitude.HasValue && !Coordinates(latitude.Value, longitude!.Value)))
                return Task.FromResult<IResult>(Results.BadRequest());
            return Discover(cs, ownerFor(r)!, query?.Trim() ?? "", latitude ?? 0, longitude ?? 0, latitude.HasValue, followed == true, coordinateSystem == "wgs84" ? "wgs84" : "gcj02", ct);
        });
        group.MapPost("/", (Center input, HttpRequest r, CancellationToken ct) => Create(cs, ownerFor(r)!, input, ct));
        group.MapPut("/{id:guid}/follow", (Guid id, HttpRequest r, CancellationToken ct) => Follow(cs, ownerFor(r)!, id, true, ct));
        group.MapDelete("/{id:guid}/follow", (Guid id, HttpRequest r, CancellationToken ct) => Follow(cs, ownerFor(r)!, id, false, ct));
        group.MapGet("/{id:guid}", (Guid id, long? since, HttpRequest r, CancellationToken ct) => Snapshot(cs, ownerFor(r)!, id, since, ct));
        group.MapPut("/{id:guid}/places", (Guid id, Place input, HttpRequest r, CancellationToken ct) => Write(cs, ownerFor(r)!, id, input, null, null, ct));
        group.MapPut("/{id:guid}/places/{place:guid}/visit", (Guid id, Guid place, HttpRequest r, CancellationToken ct) =>
            Write(cs, ownerFor(r)!, id, null, place, null, ct));
        group.MapPut("/{id:guid}/places/{place:guid}/review", (Guid id, Guid place, Review input, HttpRequest r, CancellationToken ct) =>
            Write(cs, ownerFor(r)!, id, null, place, input, ct));
        group.MapGet("/{id:guid}/places/{place:guid}/reviews", (Guid id, Guid place, HttpRequest r, CancellationToken ct) =>
            Reviews(cs, ownerFor(r)!, id, place, ct));
        group.MapGet("/{id:guid}/pending", (Guid id, HttpRequest r, CancellationToken ct) =>
            Pending(cs, ownerFor(r)!, id, ct));
        group.MapPut("/{id:guid}/places/{place:guid}/approve", (Guid id, Guid place, HttpRequest r, CancellationToken ct) =>
            Approve(cs, ownerFor(r)!, id, place, ct));
    }

    private static bool Coordinates(double lat, double lon) => lat is >= 0 and <= 60 && lon is >= 70 and <= 140;
    private static bool Valid(string? value, int max) => value?.Trim().Length is > 0 && value.Trim().Length <= max;
    private static NpgsqlCommand Command(NpgsqlConnection db, NpgsqlTransaction? tx, string sql, params (string, object)[] args)
    {
        var cmd = new NpgsqlCommand(sql, db, tx);
        foreach (var (key, value) in args) cmd.Parameters.AddWithValue(key, value);
        return cmd;
    }

    private static async Task<IResult> ReadJson(NpgsqlCommand cmd, CancellationToken ct)
    {
        await using var query = cmd;
        return await query.ExecuteScalarAsync(ct) is string data ? Results.Text(data, "application/json") : Results.NotFound();
    }

    private static async Task<IResult> Discover(string cs, string owner, string query, double lat, double lon, bool geo, bool followed, string system, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        return await ReadJson(Command(db, null, $"""
            SELECT coalesce(jsonb_agg(to_jsonb(found)), '[]')::text FROM (
                SELECT id,name,latitude,longitude,{Membership} AS followed,{Distance} AS "distanceMeters"
                FROM dining_food_maps m WHERE (@query='' OR strpos(lower(name), lower(@query))>0)
                 AND (NOT @followed OR {Membership})
                 AND (NOT @geo OR (coordinate_system=@system AND {Distance}<=10000))
                ORDER BY CASE WHEN @geo THEN {Distance} ELSE 0 END,name,id LIMIT 100
            ) found
            """, ("owner",owner), ("query",query), ("lat",lat), ("lon",lon), ("geo",geo), ("followed",followed), ("system",system)), ct);
    }

    private static async Task<IResult> Create(string cs, string owner, Center input, CancellationToken ct)
    {
        if (input.Id == Guid.Empty || !Valid(input.Name, 100) || input.CoordinateSystem is not ("gcj02" or "wgs84") ||
            !Coordinates(input.Latitude,input.Longitude)) return Results.BadRequest();
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        await using var gate = Command(db, tx, "SELECT pg_advisory_xact_lock(705221820)");
        await gate.ExecuteNonQueryAsync(ct);
        await using var close = Command(db, tx, $"""
            SELECT id,name,(id=@id AND owner_id=@owner) FROM dining_food_maps
            WHERE id=@id OR (coordinate_system=@system AND {Distance}<=500) ORDER BY (id=@id) DESC,{Distance} LIMIT 1
            """, ("lat",input.Latitude), ("lon",input.Longitude), ("id",input.Id), ("owner",owner), ("system",input.CoordinateSystem!));
        await using (var reader = await close.ExecuteReaderAsync(ct))
        {
            if (await reader.ReadAsync(ct))
                return reader.GetBoolean(2) ? Results.Ok(new { id = input.Id }) :
                    Results.Conflict(new { id = reader.GetGuid(0), name = reader.GetString(1), error = "附近已有饭圈，可先关注现有饭圈。" });
        }
        await using var insert = Command(db, tx, """
            INSERT INTO dining_food_maps(id,owner_id,name,latitude,longitude,coordinate_system) VALUES(@id,@owner,@name,@lat,@lon,@system);
            INSERT INTO dining_food_map_follows(map_id,user_id) VALUES(@id,@owner)
            """, ("id",input.Id), ("owner",owner), ("name",input.Name!.Trim()), ("lat",input.Latitude), ("lon",input.Longitude), ("system",input.CoordinateSystem!));
        await insert.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return Results.Ok(new { id = input.Id });
    }

    private static async Task<IResult> Follow(string cs, string owner, Guid id, bool follow, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var cmd = Command(db, null, follow ? """
            INSERT INTO dining_food_map_follows(map_id,user_id)
            SELECT id,@owner FROM dining_food_maps WHERE id=@id ON CONFLICT DO NOTHING
            """ : "DELETE FROM dining_food_map_follows WHERE map_id=@id AND user_id=@owner", ("id",id), ("owner",owner));
        await cmd.ExecuteNonQueryAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> Snapshot(string cs, string owner, Guid id, long? since, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        return await ReadJson(Command(db, null, $"""
            SELECT jsonb_build_object('id', m.id, 'name', m.name, 'latitude', m.latitude, 'longitude', m.longitude,
                'radiusMeters',1000,'coordinateSystem',m.coordinate_system,'canApprove',m.owner_id=@owner,'dataVersion',m.data_version,
                'followed',{Membership},'full',(@since<0 OR @since>m.data_version),
                'places',coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'id',p.id,'name',p.name,'category',p.category,'description',p.description,
                    'latitude',p.latitude,'longitude',p.longitude,'locationText',p.location_text,
                    'x',0.5+(p.longitude-m.longitude)*111195*cos(radians(m.latitude))/2000,
                    'y',0.5-(p.latitude-m.latitude)*111195/2000,
                    'visits',(SELECT count(*) FROM dining_food_map_visits v WHERE v.place_id=p.id),
                    'rating',(SELECT round(avg(v.stars),1) FROM dining_food_map_reviews v WHERE v.place_id=p.id))
                    ORDER BY p.version,p.id) FROM dining_food_map_places p
                    WHERE p.map_id=m.id AND p.approved AND (p.version>@since OR @since>m.data_version)), '[]'))::text
            FROM dining_food_maps m WHERE m.id=@id AND {Membership}
            """, ("id",id), ("owner",owner), ("since",since ?? -1)), ct);
    }

    private static async Task<IResult> Reviews(string cs, string owner, Guid id, Guid place, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        return await ReadJson(Command(db, null, $"""
            SELECT coalesce((SELECT jsonb_agg(to_jsonb(details)) FROM (
                SELECT stars,note FROM dining_food_map_reviews WHERE place_id=p.id AND note<>'' ORDER BY user_id LIMIT 100
            ) details),'[]')::text FROM dining_food_maps m JOIN dining_food_map_places p ON p.map_id=m.id
            WHERE m.id=@id AND p.id=@place AND p.approved AND {Membership}
            """, ("id",id), ("owner",owner), ("place",place)), ct);
    }

    private static async Task<IResult> Pending(string cs, string owner, Guid id, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        return await ReadJson(Command(db, null, """
            SELECT coalesce((SELECT jsonb_agg(to_jsonb(items)) FROM (
                SELECT p.id,p.name,p.category,p.location_text AS "locationText",p.description,p.latitude,p.longitude
                FROM dining_food_map_places p WHERE p.map_id=m.id AND NOT p.approved ORDER BY p.version LIMIT 100
            ) items),'[]')::text FROM dining_food_maps m WHERE m.id=@id AND m.owner_id=@owner
            """, ("id",id), ("owner",owner)), ct);
    }

    private static async Task<IResult> Approve(string cs, string owner, Guid id, Guid place, CancellationToken ct)
    {
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        await using var bump = Command(db, tx, """
            UPDATE dining_food_maps SET data_version=data_version+1 WHERE id=@id AND owner_id=@owner RETURNING data_version
            """, ("id",id), ("owner",owner));
        if (await bump.ExecuteScalarAsync(ct) is not long version) return Results.NotFound();
        await using var approve = Command(db, tx, """
            UPDATE dining_food_map_places SET approved=true,version=@version WHERE id=@place AND map_id=@id AND NOT approved
            """, ("place",place), ("id",id), ("version",version));
        if (await approve.ExecuteNonQueryAsync(ct) != 1) return Results.NotFound();
        await tx.CommitAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> Write(string cs, string owner, Guid id, Place? input, Guid? place, Review? review, CancellationToken ct)
    {
        if (review is not null && (review.Stars is < 1 or > 5 || review.Note?.Length > 1000)) return Results.BadRequest();
        if (input is not null && (input.Id == Guid.Empty || input.CoordinateSystem is not ("gcj02" or "wgs84") ||
            !Coordinates(input.Latitude,input.Longitude) || !Valid(input.Name,100) || !Valid(input.Category,80) ||
            !Valid(input.LocationText,200) || input.Description?.Length > 1000)) return Results.BadRequest();
        await using var db = new NpgsqlConnection(cs);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        await using var bump = Command(db, tx, $"""
            UPDATE dining_food_maps m SET data_version=data_version+1 WHERE id=@id AND {Membership} RETURNING data_version
            """, ("id",id), ("owner",owner));
        if (await bump.ExecuteScalarAsync(ct) is not long version) return Results.NotFound();
        if (input is not null)
        {
            await using var add = Command(db, tx, $"""
                INSERT INTO dining_food_map_places(id,map_id,owner_id,latitude,longitude,name,category,location_text,description,version)
                SELECT @place,id,@owner,@lat,@lon,@name,@category,@location,@description,@version
                FROM dining_food_maps WHERE id=@id AND coordinate_system=@system AND {Distance}<=1000
                ON CONFLICT (id) DO UPDATE SET latitude=excluded.latitude,longitude=excluded.longitude,
                    name=excluded.name,category=excluded.category,location_text=excluded.location_text,
                    description=excluded.description,version=excluded.version
                WHERE dining_food_map_places.owner_id=@owner AND dining_food_map_places.map_id=@id AND NOT dining_food_map_places.approved
                """, ("place",input.Id), ("id",id), ("owner",owner), ("lat",input.Latitude), ("lon",input.Longitude),
                ("name",input.Name!.Trim()), ("category",input.Category!.Trim()), ("location",input.LocationText!.Trim()),
                ("description",input.Description?.Trim() ?? ""), ("version",version), ("system",input.CoordinateSystem!));
            if (await add.ExecuteNonQueryAsync(ct) != 1) return Results.BadRequest(new { error = "地点需位于饭圈 1 公里范围内，且仅能编辑自己添加的地点。" });
        }
        else
        {
            await using var touch = Command(db, tx, "UPDATE dining_food_map_places SET version=@version WHERE id=@place AND map_id=@id AND approved",
                ("version",version), ("place",place!.Value), ("id",id));
            if (await touch.ExecuteNonQueryAsync(ct) != 1) return Results.NotFound();
            await using var action = review is null ? Command(db, tx, """
                INSERT INTO dining_food_map_visits(place_id,user_id) VALUES(@place,@owner) ON CONFLICT DO NOTHING
                """, ("place",place.Value), ("owner",owner)) : Command(db, tx, """
                INSERT INTO dining_food_map_reviews(place_id,user_id,stars,note) VALUES(@place,@owner,@stars,@note)
                ON CONFLICT(place_id,user_id) DO UPDATE SET stars=excluded.stars,note=excluded.note
                """, ("place",place.Value), ("owner",owner), ("stars",(short)review.Stars), ("note",review.Note?.Trim() ?? ""));
            if (await action.ExecuteNonQueryAsync(ct) == 0) return Results.NoContent();
        }
        await tx.CommitAsync(ct);
        return Results.NoContent();
    }
}
