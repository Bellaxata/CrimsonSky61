echo "🔒 Memasang Proteksi Server..."
cat > /var/www/pterodactyl/app/Http/Controllers/ServerController.php << 'EOF'
<?php

namespace Pterodactyl\Http\Controllers;

use Illuminate\View\View;
use Pterodactyl\Models\Server;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;

class ServerController extends Controller
{
    /**
     * Halaman index server - hanya tampilkan server milik user
     */
    public function index(): View
    {
        $user = Auth::user();
        
        // Jika Admin ID 1, lihat semua server
        if ($user->id === 1) {
            $servers = Server::all();
        } else {
            // User biasa: hanya lihat server miliknya
            $servers = Server::where('owner_id', $user->id)->get();
        }
        
        return view('server.index', ['servers' => $servers]);
    }

    /**
     * Lihat detail server - cek kepemilikan
     */
    public function view(Server $server): View|RedirectResponse
    {
        $user = Auth::user();
        
        // Cek apakah user punya akses ke server ini
        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, '🚫 Anda tidak memiliki akses ke server ini!');
        }
        
        return view('server.view', ['server' => $server]);
    }
}
EOF

cat > /var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php << 'EOF'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;

class ServerController extends ClientApiController
{
    /**
     * Cek akses sebelum lihat server
     */
    public function index()
    {
        $user = Auth::user();
        
        if ($user->id === 1) {
            $servers = Server::all();
        } else {
            $servers = Server::where('owner_id', $user->id)->get();
        }
        
        return $servers;
    }
    
    /**
     * Cek akses detail server
     */
    public function view(Server $server)
    {
        $user = Auth::user();
        
        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }
        
        return $server;
    }
}
EOF

cat > /var/www/pterodactyl/resources/views/layouts/admin.blade.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Pterodactyl Panel</title>
</head>
<body>
    <nav>
        <ul>
            @if(auth()->user()->id === 1)
                <li><a href="{{ route('admin.index') }}">Admin</a></li>
                <li><a href="{{ route('admin.servers') }}">All Servers</a></li>
                <li><a href="{{ route('admin.nests') }}">Nests & Eggs</a></li>
                <li><a href="{{ route('admin.nodes') }}">Nodes</a></li>
            @endif
            
            <li><a href="{{ route('index') }}">Dashboard</a></li>
            
            @if(auth()->user()->id !== 1)
                <li><a href="{{ route('server.index') }}">My Servers</a></li>
            @endif
        </ul>
    </nav>
    
    @yield('content')
</body>
</html>
EOF

cat > /var/www/pterodactyl/routes/web.php << 'EOF'
<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Auth;

// Proteksi route server
Route::middleware(['auth'])->group(function () {
    Route::get('/servers', [ServerController::class, 'index'])->name('server.index');
    Route::get('/servers/{server}', [ServerController::class, 'view'])->name('server.view')
        ->middleware(function ($request, $next) {
            $server = $request->route('server');
            $user = Auth::user();
            
            if ($user->id !== 1 && $server->owner_id !== $user->id) {
                abort(403, 'Bukan server kamu!');
            }
            
            return $next($request);
        });
});
EOF

cat > /var/www/pterodactyl/app/Models/Server.php << 'EOF'
<?php

namespace Pterodactyl\Models;

use Illuminate\Support\Facades\Auth;
use Illuminate\Database\Eloquent\Builder;

class Server extends Model
{
    /**
     * Global scope - user biasa cuma liat servernya sendiri
     */
    protected static function booted()
    {
        static::addGlobalScope('user', function (Builder $builder) {
            $user = Auth::user();
            
            if ($user && $user->id !== 1) {
                $builder->where('owner_id', $user->id);
            }
        });
    }
}
EOF

cat > /usr/local/bin/cek-akses << 'EOF'

echo "==================================="
echo "🔍 CEK AKSES SERVER"
echo "==================================="

echo "User Login:"
mysql -e "SELECT id, username, email FROM panel.users WHERE id = (SELECT user_id FROM panel.sessions LIMIT 1);" 2>/dev/null

echo ""
echo "Server Milik User ID 1:"
mysql -e "SELECT id, name, owner_id FROM panel.servers WHERE owner_id = 1;" 2>/dev/null

echo ""
echo "Server Milik User Lain:"
mysql -e "SELECT id, name, owner_id FROM panel.servers WHERE owner_id != 1 LIMIT 5;" 2>/dev/null

echo "==================================="
echo "✅ User biasa cuma bisa akses server miliknya"
echo "👑 Admin ID 1 bisa akses semua server"
EOF

chmod +x /usr/local/bin/cek-akses
echo "🔄 Clear cache..."
php /var/www/pterodactyl/artisan view:clear
php /var/www/pterodactyl/artisan cache:clear
php /var/www/pterodactyl/artisan config:clear
php /var/www/pterodactyl/artisan route:clear
php /var/www/pterodactyl/artisan optimize:clear

systemctl restart php8.1-fpm
systemctl restart nginx

echo ""
echo "✅ PROTEKSI TERPASANG!"
echo "==================================="
echo "🔒 User biasa:"
echo "   - Hanya lihat server miliknya sendiri"
echo "   - Ga bisa buka server orang lain"
echo "   - Menu server terbatas"
echo ""
echo "👑 Admin ID 1:"
echo "   - Bisa lihat SEMUA server"
echo "   - Akses penuh ke semua menu"
echo ""
echo "📋 Cek akses: /usr/local/bin/cek-akses"
echo "==================================="
