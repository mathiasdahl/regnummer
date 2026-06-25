(function () {
  "use strict";

  var QUOTES = [
    "Ka-chow! Ännu ett nummer på vägen!",
    "Du är snabbare än Lightning McQueen!",
    "Route 999 — ett steg närmare mållinjen!",
    "Radiator Springs skulle vara stolt!",
    "Full gas — jakten fortsätter!",
    "Piston Cup-känsla — snyggt hittat!",
    "Mack skulle blinka med lamporna av stolthet!",
    "Ett nummer till längs den oändliga vägen!",
    "Sally skulle ge dig tummen upp!",
    "Mater säger: det där var ett riktigt fint fynd!",
    "Ingen omkörning — du leder racet!",
    "Checkered flag i sikte — fortsätt så!",
  ];

  function setLocationMsg(text, isError) {
    var el = document.getElementById("location-msg");
    if (!el) return;
    el.textContent = text || "";
    el.style.color = isError ? "#991b1b" : "";
  }

  function formatPlace(data) {
    var addr = data && data.address;
    if (!addr) return data.display_name || "";

    return (
      addr.city ||
      addr.town ||
      addr.village ||
      addr.municipality ||
      addr.county ||
      addr.state ||
      data.display_name ||
      ""
    );
  }

  function reverseGeocode(lat, lon) {
    var url =
      "https://nominatim.openstreetmap.org/reverse?format=json&lat=" +
      encodeURIComponent(lat) +
      "&lon=" +
      encodeURIComponent(lon);

    return fetch(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": "RegnummerEmacsApp/1.0 (local hobby project)",
      },
    }).then(function (response) {
      if (!response.ok) {
        throw new Error("Geokodning misslyckades");
      }
      return response.json();
    });
  }

  function fetchLocation() {
    var input = document.getElementById("location");
    if (!input) return;

    if (!navigator.geolocation) {
      setLocationMsg("Webbläsaren stöder inte platstjänster.", true);
      return;
    }

    setLocationMsg("Hämtar plats…");

    navigator.geolocation.getCurrentPosition(
      function (pos) {
        var lat = pos.coords.latitude;
        var lon = pos.coords.longitude;

        reverseGeocode(lat, lon)
          .then(function (data) {
            var place = formatPlace(data);
            if (place) {
              input.value = place;
              setLocationMsg("Plats hämtad.");
            } else {
              setLocationMsg("Kunde inte tolka platsnamn.", true);
            }
          })
          .catch(function () {
            setLocationMsg("Kunde inte slå upp platsnamn.", true);
          });
      },
      function (err) {
        var msg = "Kunde inte hämta plats.";
        if (err.code === 1) {
          msg = "Platstillgång nekad.";
        }
        setLocationMsg(msg, true);
      },
      { enableHighAccuracy: false, timeout: 15000, maximumAge: 60000 }
    );
  }

  function randomQuote() {
    return QUOTES[Math.floor(Math.random() * QUOTES.length)];
  }

  function createFireworks(canvas) {
    var ctx = canvas.getContext("2d");
    var particles = [];
    var running = true;
    var start = performance.now();
    var duration = 4000;

    function resize() {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    }

    resize();
    window.addEventListener("resize", resize);

    function burst(x, y) {
      var colors = ["#e02020", "#e8c872", "#b85c28", "#7ec8e8", "#4a9fd4", "#fff8ee"];
      var color = colors[Math.floor(Math.random() * colors.length)];
      var count = 30 + Math.floor(Math.random() * 20);
      for (var i = 0; i < count; i++) {
        var angle = (Math.PI * 2 * i) / count + Math.random() * 0.3;
        var speed = 2 + Math.random() * 4;
        particles.push({
          x: x,
          y: y,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          life: 1,
          decay: 0.012 + Math.random() * 0.01,
          color: color,
          size: 2 + Math.random() * 2,
        });
      }
    }

    function tick(now) {
      if (!running) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      if (Math.random() < 0.08) {
        burst(
          canvas.width * (0.2 + Math.random() * 0.6),
          canvas.height * (0.2 + Math.random() * 0.4)
        );
      }

      particles = particles.filter(function (p) {
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.04;
        p.life -= p.decay;
        if (p.life <= 0) return false;

        ctx.globalAlpha = Math.max(p.life, 0);
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();
        return true;
      });

      ctx.globalAlpha = 1;

      if (now - start < duration) {
        requestAnimationFrame(tick);
      } else {
        running = false;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
      }
    }

    burst(canvas.width * 0.5, canvas.height * 0.35);
    requestAnimationFrame(tick);

    return function stop() {
      running = false;
    };
  }

  function showCelebration(registered) {
    var overlay = document.createElement("div");
    overlay.id = "celebration-overlay";

    var canvas = document.createElement("canvas");
    canvas.id = "fireworks-canvas";

    var content = document.createElement("div");
    content.className = "celebration-content";
    content.innerHTML =
      "<h2>Ka-chow!</h2>" +
      "<p class=\"celebration-number\">" +
      registered +
      "</p>" +
      "<p class=\"celebration-quote\">" +
      randomQuote() +
      "</p>" +
      "<p class=\"celebration-hint\">Klicka för att fortsätta</p>";

    overlay.appendChild(canvas);
    overlay.appendChild(content);
    document.body.appendChild(overlay);

    var stopFireworks = createFireworks(canvas);

    function dismiss() {
      stopFireworks();
      overlay.remove();
      history.replaceState(null, "", window.location.pathname);
    }

    overlay.addEventListener("click", dismiss);
    setTimeout(dismiss, 5000);
  }

  function maybeCelebrate() {
    var params = new URLSearchParams(window.location.search);
    var registered = params.get("registered");
    if (registered) {
      showCelebration(registered);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    var btn = document.getElementById("location-btn");
    if (btn) {
      btn.addEventListener("click", fetchLocation);
    }
    maybeCelebrate();
  });
})();
