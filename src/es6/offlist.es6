import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";
import Mustache from "mustache/mustache";

const pageId = "offlist";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  $(".btn-offlist-order-edit").on("click", (e) => {
    e.preventDefault();
    let $target = $(e.target);
    let url = $target.closest(".reserved-list").data("url");
    let orderId = $target.closest(".card.reserved").data("order-id");
    console.log(`edit clicked: orderId(${orderId}) url(${url})`);
    return false;
  });

  $(".btn-offlist-order-remove").on("click", (e) => {
    e.preventDefault();
    let $target = $(e.target);
    let url = $target.closest(".reserved-list").data("url");
    let $card = $target.closest(".card.reserved");
    let orderId = $card.data("order-id");
    let bookingYmd = $card.data("booking-ymd");
    let bookingHms = $card.data("booking-hms");
    console.log(`remove clicked: orderId(${orderId}) url(${url})`);

    let modal = bootbox.confirm({
      title: Mustache.render($("#template-offlist-modal-remove-title").html()),
      message: Mustache.render($("#template-offlist-modal-remove-message").html(), { "bookingYmd": bookingYmd, "bookingHms": bookingHms }),
      locale: "ko",
      buttons: {
        confirm: { label: "삭제", className: "btn-primary" },
        cancel:  { label: "취소", className: "btn-danger"  },
      },
      callback: (result) => {
        if (result) {
          console.log(`have to delete: orderId(${orderId})`);
          $card.remove();
          if ( $(".card.reserved").length == 0 ) {
            console.log("all bookings are removed");
            $(".offlist-booking-new-bottom-button").removeClass("d-flex").addClass("d-none");
            $(".offlist-booking-new-bottom-message").removeClass("d-none");
          }
        }
        else {
          // do nothing
        }
        return true;
      }
    });
    modal.animate({ scrollTop: 0 }, "slow");

    return false;
  });

  $(".btn-offlist-next").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    // success
    window.location = `${$target.data("url")}`;

    return false;
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}
