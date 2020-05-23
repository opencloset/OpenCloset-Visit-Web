import "./lib/import-jquery";
import session from "./lib/session";
import moment from "moment/src/moment";
import Mustache from "mustache/mustache";

const pageId = "offdate";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  registerCallbackDatetimeChange();
  registerCallbackBookingTimeListClick();
  registerCallbackNextClick();
  loadSession();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallbackDatetimeChange = () => {
  // https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/change_event
  // https://stackoverflow.com/questions/3025396/how-do-you-handle-a-form-change-in-jquery
  // https://stackoverflow.com/questions/6458840/detecting-input-change-in-jquery
  $("#bookingYmd").on("change input paste", e => {
    let ymd = $("#bookingYmd").val();
    updateAvailableBookingList(ymd);
    e.preventDefault();
  });

  // https://stackoverflow.com/questions/31858920/jquery-bootstrap-datetimepicker-change-event
  $("#offdateDatetimepicker").on("dp.change", e => {
    // use specific "YYYY-MM-DD" rather than e.date._f
    // since somtimes e.date._f is not ready to use
    let formatedValue = e.date.format("YYYY-MM-DD");
    updateAvailableBookingList(formatedValue);
  });
};

const registerCallbackBookingTimeListClick = () => {
  $(".offdate-booking-hm-list input[type=radio]").on("click", e => {
    updateNextButton();
    $(".custom-control").removeClass("selected");
    $(e.target)
      .closest(".custom-control")
      .addClass("selected");
  });
};

const loadSession = () => {
  let phone = new URL(window.location.href).searchParams.get("phone");

  let ymd = moment().format("YYYY-MM-DD");
  if (phone) {
    let data = session.load(phone);
    if (data.ymd) {
      ymd = data.ymd;
    }
  }
  $("#bookingYmd").val(ymd);
  $("#bookingYmd").trigger("input");
};

const registerCallbackNextClick = () => {
  $("#btn-offdate-next").on("click", e => {
    e.preventDefault();

    let phone = new URL(window.location.href).searchParams.get("phone");
    if (!phone) {
      return false;
    }

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let ymd = $("#bookingYmd").val();
    if (!ymd) {
      return false;
    }

    let bookingId = $("input[name=booking-hm]:checked").val();
    if (!(bookingId && bookingId > 0)) {
      return false;
    }

    let data = session.load(phone);
    data.ymd = ymd;
    data.booking_id = bookingId;
    session.save(phone, data);

    // success
    let reqUrl = new URL($target.data("url"), window.location.origin);
    window.location = reqUrl.href;

    return false;
  });
};

const updateAvailableBookingList = ymd => {
  if (ymd.match(/^\d{4}-\d{2}-\d{2}$/) === null) {
    return;
  }

  let templateSuccess = $("#template-booking-list-success").html();
  let templateFailure = $("#template-booking-list-failure").html();
  let $bookingHmList = $(".offdate-booking-hm-list");
  let now = moment();

  let reqUrl = new URL(
    `/api/gui/booking-list.json${window.location.search}`,
    window.location.origin,
  );
  reqUrl.searchParams.set("ymd", ymd);
  reqUrl.searchParams.set("include_empty", 1);
  fetch(reqUrl, { method: "GET" })
    .then(response => {
      if (!response.ok) {
        throw Error(response.statusText);
      }
      return response;
    })
    .then(response => response.json())
    .then(resData => {
      let countAvailable = 0;
      resData.forEach(val => {
        let valDate = moment(val.date);
        let isRemain = val.slot > val.user_count;
        let isNew = now.unix() < valDate.unix();

        val.hm = val.date.substring(11, 16);
        val.remainSlot = isRemain ? val.slot - val.user_count : 0;
        val.breakTime = false;
        val.display = false;
        val.old = !isNew;

        // break time
        let weekDay = valDate.day();
        switch (weekDay) {
          case 1: // Mon
          case 2: // Tue
          case 3: // Wed
          case 4: // Thu
          case 5: // Fri
            let hm = valDate.format("HH:mm");
            switch (hm) {
              case "15:30":
              case "16:00":
              case "16:30":
                val.breakTime = true;
                val.remainSlot = 0;
            }
          case 0: // Sun
          case 6: // Sat
        }

        // display
        {
          let hmInt = parseInt(valDate.format("Hmm"), 10);
          switch (weekDay) {
            case 1: // Mon
            case 2: // Tue
            case 3: // Wed
            case 4: // Thu
            case 5: // Fri
              if (900 <= hmInt && hmInt <= 1900) {
                val.display = true;
              }
            case 0: // Sun
            case 6: // Sat
              if (900 <= hmInt && hmInt <= 1700) {
                val.display = true;
              }
          }
        }

        if (isRemain && isNew && val.display && !val.breakTime) {
          countAvailable++;
        }
      });
      if (countAvailable <= 0) {
        $bookingHmList.html(templateFailure);
        updateNextButton();
        return;
      }

      $bookingHmList.html(
        Mustache.render(templateSuccess, { bookingList: resData }),
      );
      {
        let phone = new URL(window.location.href).searchParams.get("phone");
        if (phone) {
          let data = session.load(phone);
          if (data.booking_id) {
            $(`input[name=booking-hm][value=${data.booking_id}]`).prop("checked", true);
          }
        }
      }
      registerCallbackBookingTimeListClick();
      updateNextButton();
    })
    .catch(error => {
      $bookingHmList.html(templateFailure);
      updateNextButton();
    });
};

const updateNextButton = () => {
  let bookingId = $("input[name=booking-hm]:checked").val();

  let $nextBtn = $("#btn-offdate-next");
  if (bookingId && bookingId > 0) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
